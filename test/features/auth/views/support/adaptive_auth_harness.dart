import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/models/backend_config.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/models/user.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/providers/openwebui_accounts_controller.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/optimized_storage_service.dart';
import 'package:conduit/features/auth/views/authentication_page.dart';
import 'package:conduit/l10n/app_localizations.dart';
import 'package:conduit/l10n/conduit_localizations.dart';
import 'package:conduit/shared/widgets/platform_ui/platform_ui.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod/misc.dart' show Override;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class AdaptiveAuthHarness {
  AdaptiveAuthHarness({
    required this.server,
    this.platform = TargetPlatform.android,
    this.backendConfig,
    this.disableAnimations = false,
    this.textScaler,
    this.authActions,
    this.userId,
    this.addingAccountFrom,
    this.abandonablePendingSignIn = false,
    this.accountsController,
    this.savedServersError,
    this.replyBeingWritten = false,
  }) {
    when(() => _storage.getAuthTokenStrict()).thenAnswer((_) async => '');
    when(() => _storage.getSavedCredentialsStrict())
        .thenAnswer((_) async => null);
    when(() => _storage.saveLocalUser(null)).thenAnswer((_) async {});
    when(() => _storage.saveLocalUserAvatar(null)).thenAnswer((_) async {});
    when(() => _storage.getReviewerMode()).thenAnswer((_) async => false);
    if (savedServersError case final error?) {
      when(() => _storage.getOpenWebUiRegistryStrict())
          .thenAnswer((_) async => throw error);
    }
    if (authActions != null) {
      // A sign-in attempt first saves the server it was opened for.
      registerFallbackValue(server);
      when(
        () => _storage.selectUnauthenticatedServerConfig(
          any(),
          canCommit: any(named: 'canCommit'),
          onRollbackUncertain: any(named: 'onRollbackUncertain'),
          publish: any(named: 'publish'),
        ),
      ).thenAnswer((_) async => true);
      registerFallbackValue(const BackendConfig());
      when(() => _storage.getLocalBackendConfig())
          .thenAnswer((_) async => null);
      when(() => _storage.saveLocalBackendConfig(any()))
          .thenAnswer((_) async {});
      when(() => _storage.saveLocalTransportOptions(any()))
          .thenAnswer((_) async {});
      when(() => _storage.saveRefreshToken(any(), any()))
          .thenAnswer((_) async {});
    }
  }

  final ServerConfig server;
  final TargetPlatform platform;
  final BackendConfig? backendConfig;
  final bool disableAnimations;
  final TextScaler? textScaler;

  /// Replaces the sign-in actions, so a test controls the outcome of an attempt.
  final AuthActions? authActions;

  /// The signed-in Open WebUI user, when a test needs one.
  final String? userId;

  /// Overrides a test adds beyond the harness's own (e.g. the login seam).
  List<Override> extraOverrides = const [];

  /// The account another one is being added from, if one is.
  final String? addingAccountFrom;

  /// Whether the active account is an added one whose sign-in never
  /// finished, which sign-in pages offer to drop.
  final bool abandonablePendingSignIn;

  /// Replaces the account actions, so a test sees which it asked for.
  final OpenWebUiAccountsController? accountsController;

  /// What reading the saved servers fails with, as a Keychain error does.
  final Object? savedServersError;

  /// Whether a reply is still being written that leaving the active account
  /// would stop.
  final bool replyBeingWritten;

  /// How many times the replies being written were stopped.
  int repliesStopped = 0;

  /// The device storage, for a test to see what was saved.
  OptimizedStorageService get storage => _storage;
  final _MockOptimizedStorageService _storage = _MockOptimizedStorageService();
  final ErrorWidgetBuilder _previousErrorWidgetBuilder = ErrorWidget.builder;
  final void Function(FlutterErrorDetails)? _previousFlutterOnError =
      FlutterError.onError;

  /// When set, the route rebuilds the page as the app's router does when the
  /// route's `extra` is gone: with no server or backend config.
  final routeExtraLost = ValueNotifier<bool>(false);

  late GoRouter router;
  bool _disposed = false;

  Widget build({required String initialLocation}) {
    PlatformUiCapabilities.debugPlatformOverride = platform;
    router = GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(
          path: Routes.authentication,
          name: RouteNames.authentication,
          builder: (_, _) => ValueListenableBuilder<bool>(
            valueListenable: routeExtraLost,
            builder: (_, extraLost, _) => extraLost
                ? const AuthenticationPage()
                : AuthenticationPage(
                    serverConfig: server,
                    backendConfig: backendConfig,
                  ),
          ),
        ),
        GoRoute(
          path: Routes.chat,
          name: RouteNames.chat,
          builder: (_, _) => const SizedBox(key: ValueKey<String>('chat')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        if (authActions != null) ...[
          authActionsProvider.overrideWithValue(authActions!),
          // A sign-in attempt first waits for the API client of the selected
          // server.
          apiServiceProvider.overrideWithValue(_selectedServerApi()),
        ],
        optimizedStorageServiceProvider.overrideWithValue(_storage),
        if (addingAccountFrom != null)
          accountAdditionOriginProvider.overrideWith(
            () => _AddingAccountFrom(addingAccountFrom!),
          ),
        // Answered here, not read from the mocked storage: a read that fails
        // keeps the connection page from leaving an addition.
        pendingSignInAbandonableProvider.overrideWith(
          (_) async => abandonablePendingSignIn,
        ),
        if (replyBeingWritten) ...[
          accountChangeReplyGuardProvider.overrideWithValue(() => true),
          accountChangeStopRepliesProvider.overrideWithValue(
            () => repliesStopped++,
          ),
        ],
        if (accountsController != null)
          openWebUiAccountsControllerProvider.overrideWithValue(
            accountsController!,
          ),
        activeServerProvider.overrideWith((_) async => server),
        if (userId case final userId?)
          currentUserProvider2.overrideWithValue(
            User(
              id: userId,
              username: 'ada',
              email: 'ada@example.com',
              role: 'user',
            ),
          ),
        ...extraOverrides,
      ],
      child: MaterialApp.router(
        theme: ThemeData(platform: platform),
        localizationsDelegates: conduitLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            textScaler: textScaler,
          ),
          child: child!,
        ),
        routerConfig: router,
      ),
    );
  }

  ApiService _selectedServerApi() {
    final api = _MockApiService();
    when(() => api.authToken).thenReturn(null);
    when(() => api.serverConfig).thenReturn(server);
    return api;
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    dispose();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    PlatformUiCapabilities.debugPlatformOverride = null;
    router.dispose();
    routeExtraLost.dispose();
    ErrorWidget.builder = _previousErrorWidgetBuilder;
    FlutterError.onError = _previousFlutterOnError;
  }
}

final class _AddingAccountFrom extends AccountAdditionOrigin {
  _AddingAccountFrom(this.accountId);

  final String accountId;

  @override
  String? build() => accountId;
}

class _MockApiService extends Mock implements ApiService {}

class _MockOptimizedStorageService extends Mock
    implements OptimizedStorageService {}
