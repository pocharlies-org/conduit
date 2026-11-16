import 'package:checks/checks.dart';
import 'package:conduit/core/auth/pkce_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:conduit_core/auth/owui_oidc.dart';
import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:conduit/features/auth/views/authentication_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'support/adaptive_auth_harness.dart';

void main() {
  const server = ServerConfig(
    id: 'server-1',
    name: 'Open WebUI',
    url: 'https://open-webui.example',
    isActive: true,
  );

  test('authentication server ownership requires the full tokenless transport identity', () {
    const expected = ServerConfig(
      id: 'server-1',
      name: 'Open WebUI',
      url: 'https://open-webui.example',
      apiKey: 'legacy-token-that-selection-must-strip',
      customHeaders: {'Cookie': 'proxy=session'},
      isActive: true,
      allowSelfSignedCertificates: true,
      mtlsCertificateChainPem: 'certificate',
      mtlsPrivateKeyPem: 'private-key',
      mtlsPrivateKeyPassword: 'passphrase',
    );
    final selected = expected.copyWith(
      url: 'https://OPEN-WEBUI.example/',
      apiKey: null,
    );

    check(authenticationServerMatchesSelection(selected, expected)).isTrue();
    for (final mismatched in <ServerConfig>[
      selected.copyWith(id: 'replacement-id'),
      selected.copyWith(url: 'https://replacement.example'),
      selected.copyWith(apiKey: 'stale-bearer'),
      selected.copyWith(customHeaders: const {'Cookie': 'proxy=other'}),
      selected.copyWith(allowSelfSignedCertificates: false),
      selected.copyWith(mtlsCertificateChainPem: 'other-certificate'),
      selected.copyWith(mtlsPrivateKeyPem: 'other-private-key'),
      selected.copyWith(mtlsPrivateKeyPassword: 'other-passphrase'),
    ]) {
      check(authenticationServerMatchesSelection(mismatched, expected))
          .isFalse();
    }
    check(authenticationServerMatchesSelection(null, expected)).isFalse();

    final workerManager = WorkerManager();
    final api = ApiService(
      serverConfig: selected,
      workerManager: workerManager,
    );
    addTearDown(api.dispose);
    addTearDown(workerManager.dispose);
    check(authenticationApiMatchesSelection(api, expected)).isTrue();

    api.updateAuthToken('prior-session-bearer');
    check(authenticationApiMatchesSelection(api, expected)).isFalse();
  });

  testWidgets(
    'sign-in only offers the login sheet',
    (tester) => _onIOS(() async {
      final harness = AdaptiveAuthHarness(server: server);
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        harness.build(initialLocation: Routes.authentication),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sign in with SSO'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('pkce_sign_in_description')),
        findsOneWidget,
      );

      await harness.unmount(tester);
    }),
  );

  testWidgets(
    'a completed login makes the exchanged JWT the session',
    (tester) => _onIOS(() async {
      final actions = _RecordingAuthActions();
      final harness = AdaptiveAuthHarness(
        server: server,
        authActions: actions,
        userId: 'user-1',
      );
      addTearDown(harness.dispose);
      harness.extraOverrides = [
        pkceSignInProvider.overrideWithValue(
          () async =>
              const OwuiSignIn(jwt: 'owui-jwt', refreshToken: 'kc-refresh'),
        ),
      ];

      await tester.pumpWidget(
        harness.build(initialLocation: Routes.authentication),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in with SSO'));
      await tester.pumpAndSettle();

      expect(actions.tokens, ['owui-jwt']);
      // The Keycloak refresh token is filed under the user it belongs to.
      verify(() => harness.storage.saveRefreshToken('user-1', 'kc-refresh'))
          .called(1);

      await harness.unmount(tester);
    }),
  );

  testWidgets(
    'a dismissed sheet signs nobody in and shows no error',
    (tester) => _onIOS(() async {
      final actions = _RecordingAuthActions();
      final harness = AdaptiveAuthHarness(server: server, authActions: actions);
      addTearDown(harness.dispose);
      harness.extraOverrides = [
        pkceSignInProvider.overrideWithValue(() async => null),
      ];

      await tester.pumpWidget(
        harness.build(initialLocation: Routes.authentication),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in with SSO'));
      await tester.pumpAndSettle();

      expect(actions.tokens, isEmpty);
      expect(find.textContaining('We couldn\'t sign you in'), findsNothing);

      await harness.unmount(tester);
    }),
  );

  testWidgets(
    'a refused login says so and stays on the page',
    (tester) => _onIOS(() async {
      final actions = _RecordingAuthActions();
      final harness = AdaptiveAuthHarness(server: server, authActions: actions);
      addTearDown(harness.dispose);
      harness.extraOverrides = [
        pkceSignInProvider.overrideWithValue(
          () async => throw const OwuiLoginException('exchange refused'),
        ),
      ];

      await tester.pumpWidget(
        harness.build(initialLocation: Routes.authentication),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign in with SSO'));
      await tester.pumpAndSettle();

      expect(find.textContaining('We couldn\'t sign you in'), findsOneWidget);
      expect(actions.tokens, isEmpty);

      await harness.unmount(tester);
    }),
  );

  testWidgets(
    'sign-in displays a sanitized Open WebUI address',
    (tester) => _onIOS(() async {
      const serverWithSecrets = ServerConfig(
        id: 'server-with-secrets',
        name: 'Open WebUI',
        url: 'https://user:password@example.com:8443/openwebui?token=secret#private',
        isActive: true,
      );
      final harness = AdaptiveAuthHarness(server: serverWithSecrets);
      addTearDown(harness.dispose);

      await tester.pumpWidget(
        harness.build(initialLocation: Routes.authentication),
      );
      await tester.pumpAndSettle();

      expect(find.text('https://example.com:8443/openwebui'), findsOneWidget);
      expect(find.text(serverWithSecrets.url), findsNothing);
      expect(find.textContaining('user:'), findsNothing);
      expect(find.textContaining('token='), findsNothing);
      expect(find.textContaining('#private'), findsNothing);

      await harness.unmount(tester);
    }),
  );
}

/// Runs a widget test on the platform whose login sheet the page offers.
Future<void> _onIOS(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

/// Answers the token step and records what it was given.
class _RecordingAuthActions extends Fake implements AuthActions {
  final tokens = <String>[];

  @override
  Future<bool> loginWithApiKey(
    String apiKey, {
    bool rememberCredentials = false,
    String authType = 'token',
    Object? expectedServerConfig,
    bool showLoading = true,
    bool publishErrors = true,
  }) async {
    tokens.add(apiKey);
    return true;
  }
}
