import 'package:flutter/foundation.dart' show mapEquals, visibleForTesting;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:conduit_core/auth/owui_oidc.dart';
import 'package:conduit_core/models/backend_config.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/providers/openwebui_accounts_controller.dart';
import 'package:conduit_core/services/api_service.dart';

import 'package:conduit_core/providers/host_ports.dart'
    show signInFlowProvider;
import '../../../core/services/haptic_service.dart';
import '../../../shared/theme/theme_extensions.dart';
import '../../../shared/widgets/conduit_components.dart';
import '../../../shared/widgets/utility_components.dart';
import '../../profile/widgets/account_actions.dart'
    show abandonAddedAccount, confirmLeavingActiveAccount;

import 'package:conduit_core/auth/auth_state_manager.dart';
import 'package:conduit_core/utils/debug_logger.dart';

import 'package:conduit/l10n/app_localizations.dart';

import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';

import '../../../shared/widgets/connection_components.dart';

@visibleForTesting
String normalizeAuthenticationServerUrl(String value) {
  final trimmed = value.trim();
  final parsed = Uri.tryParse(trimmed);
  if (parsed == null || !parsed.hasScheme || parsed.host.isEmpty) {
    return trimmed;
  }

  var path = parsed.path;
  while (path.length > 1 && path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }
  if (path == '/') path = '';
  return parsed
      .replace(
        scheme: parsed.scheme.toLowerCase(),
        host: parsed.host.toLowerCase(),
        path: path,
      )
      .toString();
}

@visibleForTesting
bool authenticationServerMatchesSelection(
  ServerConfig? actual,
  ServerConfig expected,
) {
  return actual != null &&
      actual.id == expected.id &&
      actual.apiKey == null &&
      normalizeAuthenticationServerUrl(actual.url) ==
          normalizeAuthenticationServerUrl(expected.url) &&
      mapEquals(actual.customHeaders, expected.customHeaders) &&
      actual.allowSelfSignedCertificates ==
          expected.allowSelfSignedCertificates &&
      actual.mtlsCertificateChainPem == expected.mtlsCertificateChainPem &&
      actual.mtlsPrivateKeyPem == expected.mtlsPrivateKeyPem &&
      actual.mtlsPrivateKeyPassword == expected.mtlsPrivateKeyPassword;
}

/// Whether the selected server's newly-created API client is safe for sign-in.
///
/// Selection deliberately strips legacy [ServerConfig.apiKey] values, and the
/// replacement client must not inherit a bearer from the prior session.
@visibleForTesting
bool authenticationApiMatchesSelection(
  ApiService? actual,
  ServerConfig expected,
) {
  return actual != null &&
      actual.authToken == null &&
      authenticationServerMatchesSelection(actual.serverConfig, expected);
}

/// The product's only sign-in: Keycloak in the system-browser sheet (PKCE),
/// the token exchange for an Open WebUI JWT, and that JWT as the bearer.
///
/// There is no form here and nothing to fill in: the server is the seeded one,
/// the person is whoever the realm already knows, and the sheet is the real
/// browser so Google sign-in and the saved session both work.
class AuthenticationPage extends ConsumerStatefulWidget {
  final ServerConfig? serverConfig;
  final BackendConfig? backendConfig;

  const AuthenticationPage({super.key, this.serverConfig, this.backendConfig});

  @override
  ConsumerState<AuthenticationPage> createState() => _AuthenticationPageState();
}

class _AuthenticationPageState extends ConsumerState<AuthenticationPage> {
  // The route hands these over in its `extra`, which go_router does not keep
  // when it rebuilds the page from restored route information (it happened
  // on the refresh after a failed sign-in).
  late ServerConfig? _serverConfig = widget.serverConfig;
  late BackendConfig? _backendConfig = widget.backendConfig;
  String? _loginError;
  bool _isSigningIn = false;
  bool _serverConfigSaved = false;

  /// Whether the addition this page's server was saved for is still under
  /// way, when it was saved for one.
  bool Function()? _additionInProgress;

  ConnectionAttemptState get _attemptState {
    final l10n = AppLocalizations.of(context)!;
    if (_isSigningIn) {
      return ConnectionAttemptState.connecting(l10n.signingIn);
    }
    final error = _loginError;
    if (error != null) return ConnectionAttemptState.failed(error);
    return const ConnectionAttemptState.idle();
  }

  @override
  void didUpdateWidget(AuthenticationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _serverConfig = widget.serverConfig ?? _serverConfig;
    _backendConfig = widget.backendConfig ?? _backendConfig;
  }

  Future<void> _signIn() async {
    if (_isSigningIn) return;

    final l10n = AppLocalizations.of(context)!;
    if (!await _mayLeaveActiveAccount() || !mounted) return;

    setState(() {
      _isSigningIn = true;
      _loginError = null;
    });

    try {
      // Save server config on first sign-in attempt if it's a new config
      // This persists the server so the person can retry without re-adding it
      if (_serverConfig != null && !_serverConfigSaved) {
        await _saveServerConfig(_serverConfig!);
        _serverConfigSaved = true;
      }
      if (!await _signInTargetStillSelected()) {
        throw StateError(
          'The selected server changed before sign-in was ready.',
        );
      }
      if (!mounted) return;

      final signedIn = await ref.read(signInFlowProvider)?.call();
      if (!mounted || signedIn == null) return;
      final jwt = signedIn.jwt;

      if (!await _signInTargetStillSelected()) {
        throw StateError('The selected server changed during sign-in.');
      }
      final success = await ref
          .read(authActionsProvider)
          .loginWithApiKey(jwt, rememberCredentials: true);
      if (!success) {
        final authState = ref.read(authStateManagerProvider).asData?.value;
        throw Exception(authState?.error ?? l10n.loginFailed);
      }

      // The refresh token is what renews this session without the sheet. It
      // is filed under the user it belongs to, so a renewal can never mint a
      // token for a different account.
      final refreshToken = signedIn.refreshToken;
      final userId =
          ref.read(currentUserProvider2)?.id ??
          ref.read(authStateManagerProvider).asData?.value.user?.id;
      if (refreshToken != null && userId != null) {
        await ref
            .read(optimizedStorageServiceProvider)
            .saveRefreshToken(userId, refreshToken);
      }

      if (!mounted) return;
      ConduitHaptics.success();
      // Navigation is handled by the router when auth state changes.
    } on OwuiLoginException catch (error) {
      DebugLogger.error(
        'pkce-sign-in-refused',
        scope: 'auth/page',
        error: error,
      );
      if (!mounted) return;
      setState(() => _loginError = l10n.genericSignInFailed);
      ConduitHaptics.error();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loginError = _formatLoginError(e.toString()));
      ConduitHaptics.error();
    } finally {
      if (mounted) {
        setState(() {
          _isSigningIn = false;
        });
      }
    }
  }

  /// Back, except while adding another account: then Cancel, which drops it
  /// and returns to the previous account. At the app's root -- the sign-in
  /// of the seeded server, OWU-134 -- there is nothing to go back to.
  UtilityBackNavigation? _backNavigation(
    AppLocalizations l10n, {
    required bool abandonable,
  }) {
    const key = ValueKey<String>('authentication-back-button');
    if (abandonable) {
      return UtilityBackNavigation(
        label: l10n.cancel,
        buttonKey: key,
        onPressed: _cancelAddition,
      );
    }
    if (context.canPop()) {
      return UtilityBackNavigation(
        label: l10n.back,
        buttonKey: key,
        onPressed: () => context.pop(),
      );
    }
    // OWU-134: the sign-in of the seeded server is the app's root when a
    // session is owed; there is no server setup to go back to.
    return null;
  }

  /// The first attempt makes the server's new account the active one. While
  /// another account is added that leaves the one it was added from, and
  /// stops a reply still being written there, so ask first.
  Future<bool> _mayLeaveActiveAccount() async {
    if (_serverConfig == null ||
        _serverConfigSaved ||
        ref.read(accountAdditionOriginProvider) == null) {
      return true;
    }
    return confirmLeavingActiveAccount(context, ref);
  }

  Future<void> _saveServerConfig(ServerConfig config) async {
    // Saved for an added account, the server is that addition's. Left while
    // the save is slow -- Back is then only Back, with the account it was
    // added from still active -- the addition ends, and so must the save:
    // it would make the new account active, signed out, over chat.
    final addition = ref.read(accountAdditionOriginProvider) == null
        ? null
        : ref.read(accountAdditionOriginProvider.notifier).stillInProgress();
    _additionInProgress = addition;
    await ref
        .read(authStateManagerProvider.notifier)
        .selectUnauthenticatedServerConfig(config, canCommit: addition);

    final selectedServer = await ref.read(activeServerProvider.future);
    if (!authenticationServerMatchesSelection(selectedServer, config)) {
      throw StateError('The selected server changed before sign-in was ready.');
    }
    await _waitForApiService(config);

    final backendConfig = _backendConfig;
    if (backendConfig != null) {
      // The config was already verified for this server before sign-in. Keep it
      // associated with the newly active server so capability warnings and
      // transport options do not wait for another fetch after authentication.
      await ref.read(backendConfigProvider.future);
      await ref
          .read(backendConfigProvider.notifier)
          .cacheForServer(backendConfig, config.id);
    }
  }

  /// Whether what this sign-in signs in to is still selected. Cancel, or
  /// Back, while it is prepared ends the addition and makes the account it
  /// began from active again; a sign-in then would save this user's session
  /// under that account.
  ///
  /// Unreadable, it is not known to be: false, which each sign-in reports as
  /// a failure, letting the user try again.
  Future<bool> _signInTargetStillSelected() async {
    final addition = _additionInProgress;
    if (addition != null && !addition()) return false;
    final config = _serverConfig;
    if (config == null) return true;
    try {
      final selected = await ref.read(activeServerProvider.future);
      return mounted && authenticationServerMatchesSelection(selected, config);
    } catch (error, stackTrace) {
      DebugLogger.error(
        'sign-in-selection-read-failed',
        scope: 'auth/page',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// Cancel: drops the added account and returns to the account it was
  /// added from, or stays and says so when it could not be dropped.
  Future<void> _cancelAddition() async {
    if (!await abandonAddedAccount(context, ref) && mounted) {
      setState(() => _loginError = AppLocalizations.of(context)!.errorMessage);
    }
  }

  Future<void> _waitForApiService(ServerConfig selectedServer) async {
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (DateTime.now().isBefore(deadline)) {
      final api = ref.read(apiServiceProvider);
      if (authenticationApiMatchesSelection(api, selectedServer)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    throw StateError('The selected server connection was not ready in time.');
  }

  String _formatLoginError(String error) {
    final l10n = AppLocalizations.of(context)!;
    if (error.contains('accountPendingApproval')) {
      return l10n.signInAccountPendingApproval;
    } else if (error.contains('401') || error.contains('Unauthorized')) {
      return l10n.invalidCredentials;
    } else if (error.contains('redirect')) {
      return l10n.serverRedirectingHttps;
    } else if (error.contains('SocketException') ||
        error.contains('DioException')) {
      return l10n.unableToConnectServer;
    } else if (error.contains('timeout')) {
      return l10n.requestTimedOut;
    }
    return l10n.genericSignInFailed;
  }

  @override
  Widget build(BuildContext context) {
    // Listen for auth state changes to run post-login side effects.
    ref.listen<AsyncValue<AuthState>>(authStateManagerProvider, (
      previous,
      next,
    ) {
      final nextState = next.asData?.value;
      final prevState = previous?.asData?.value;
      if (mounted &&
          nextState?.isAuthenticated == true &&
          prevState?.isAuthenticated != true) {
        DebugLogger.auth(
          'Authentication successful, initializing background resources',
        );

        // Navigation is handled automatically by the router when auth state
        // changes to authenticated. Calling context.go() here can race with
        // the redirect and duplicate the shell navigator during auth recovery.
      }
    });

    final l10n = AppLocalizations.of(context)!;
    final abandonable =
        ref.watch(pendingSignInAbandonableProvider).value ?? false;

    // The system back and the edge swipe leave as Cancel does, so they cannot
    // leave an added account that never signed in as the active one.
    return PopScope(
      canPop: !abandonable,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _cancelAddition();
      },
      child: UtilityPageScaffold.auth(
        title: l10n.signIn,
        backNavigation: _backNavigation(l10n, abandonable: abandonable),
        bottomAction: _buildSignInButton(),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(),
            const SizedBox(height: Spacing.xl),
            InsetGroupedSection(
              flat: true,
              child: Text(
                l10n.ssoDescription,
                key: const ValueKey<String>('pkce_sign_in_description'),
                style: context.conduitTheme.bodyMedium?.copyWith(
                  color: context.conduitTheme.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
            if (_attemptState.isVisible) ...[
              const SizedBox(height: Spacing.md),
              ConnectionAttemptBanner(state: _attemptState),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Text(
      _serverAddressForDisplay(_resolvedServerConfig?.url),
      textAlign: TextAlign.center,
      style: AppTypography.bodySmallStyle.copyWith(
        color: context.conduitTheme.textSecondary,
        fontFamily: AppTypography.monospaceFontFamily,
      ),
    );
  }

  ServerConfig? get _resolvedServerConfig {
    final activeServerAsync = ref.watch(activeServerProvider);
    return _serverConfig ??
        activeServerAsync.maybeWhen(data: (s) => s, orElse: () => null);
  }

  String _serverAddressForDisplay(String? rawUrl) {
    if (rawUrl == null || rawUrl.trim().isEmpty) {
      return AppLocalizations.of(context)!.serverAddressUnavailable;
    }

    final value = rawUrl.trim();
    final uri = Uri.tryParse(value);
    final scheme = uri?.scheme.toLowerCase();
    if (uri == null ||
        uri.host.isEmpty ||
        (scheme != 'http' && scheme != 'https')) {
      return AppLocalizations.of(context)!.serverAddressUnavailable;
    }

    final path = uri.path == '/' ? '' : uri.path;
    return '${uri.origin}$path';
  }

  Widget _buildSignInButton() {
    final l10n = AppLocalizations.of(context)!;
    return ConduitButton(
      text: _isSigningIn ? l10n.signingIn : l10n.signInWithSso,
      onPressed: _isSigningIn || ref.read(signInFlowProvider) == null
          ? null
          : _signIn,
      isLoading: _isSigningIn,
      isFullWidth: true,
    );
  }
}
