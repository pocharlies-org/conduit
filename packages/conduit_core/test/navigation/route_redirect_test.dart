import 'dart:async';

import 'package:checks/checks.dart';
import 'package:conduit_core/auth/auth_state_manager.dart';
import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/features/workspace/models/workspace_capabilities.dart';
import 'package:conduit_core/features/workspace/providers/workspace_capabilities_provider.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/navigation/route_redirect.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:riverpod/misc.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

const _server = ServerConfig(
  id: 'server',
  name: 'Server',
  url: 'https://owui.example',
);

/// A [ProviderRead] over fixed values, so the policy runs with no container
/// and no Flutter binding. A provider the case did not set throws, which
/// shows up as a failing test when the policy starts reading something new.
///
/// OWU-134: the app is Open WebUI only, pre-configured with the one seeded
/// server. There is no backend chooser, no setup wizard and no account
/// chooser, so the only providers the redirect reads are the reviewer flag,
/// the active server, the auth navigation state, the auth snapshot and (for
/// workspace routes) the workspace capabilities.
ProviderRead _reader({
  bool reviewerMode = false,
  AsyncValue<ServerConfig?> activeServer = const AsyncData(_server),
  AuthNavigationState auth = AuthNavigationState.authenticated,
  AuthState authSnapshot = const AuthState(status: AuthStatus.unauthenticated),
  AsyncValue<WorkspaceCapabilities> capabilities = const AsyncData(
    WorkspaceCapabilities(),
  ),
}) {
  final values = <ProviderListenable<Object?>, Object?>{
    reviewerModeProvider: reviewerMode,
    activeServerProvider: activeServer,
    authNavigationStateProvider: auth,
    authStateManagerProvider: AsyncData<AuthState>(authSnapshot),
    workspaceCapabilitiesProvider: capabilities,
  };
  return <T>(ProviderListenable<T> provider) {
    if (!values.containsKey(provider)) {
      throw StateError('Unexpected provider read: $provider');
    }
    return values[provider] as T;
  };
}

/// The active server as it reads while it is fetched again: still the one
/// already known, and loading.
Future<AsyncValue<ServerConfig?>> _refreshing(ServerConfig server) async {
  final refetch = Completer<ServerConfig?>();
  var builds = 0;
  final provider = FutureProvider<ServerConfig?>(
    (ref) => builds++ == 0 ? Future.value(server) : refetch.future,
  );
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await container.read(provider.future);
  container.invalidate(provider);
  final refreshing = container.read(provider);
  check(refreshing.isLoading).isTrue();
  check(refreshing.value).equals(server);
  return refreshing;
}

void main() {
  group('resolveRouteRedirect (OWU-134: Open WebUI only)', () {
    test('reviewer mode pins the app to chat', () {
      final read = _reader(reviewerMode: true);

      check(resolveRouteRedirect(Routes.profile, read)).equals(Routes.chat);
      check(resolveRouteRedirect(Routes.chat, read)).isNull();
    });

    // The boot the story asks for: a signed-in session leaves the login for
    // chat, and a signed-out one lands on the login of the seeded server.
    test('an authenticated session leaves auth pages for chat', () {
      final read = _reader();

      check(resolveRouteRedirect(Routes.authentication, read))
          .equals(Routes.chat);
      check(resolveRouteRedirect(Routes.splash, read)).equals(Routes.chat);
      check(resolveRouteRedirect(Routes.chat, read)).isNull();
    });

    test('needsLogin sends the user to the authentication page', () {
      final read = _reader(auth: AuthNavigationState.needsLogin);

      // From any non-auth route the destination is the sign-in, never a
      // chooser or a wizard.
      check(resolveRouteRedirect(Routes.chat, read))
          .equals(Routes.authentication);
      check(resolveRouteRedirect(Routes.splash, read))
          .equals(Routes.authentication);
      check(resolveRouteRedirect(Routes.profile, read))
          .equals(Routes.authentication);
      // Already on the sign-in: stay there.
      check(resolveRouteRedirect(Routes.authentication, read)).isNull();
    });

    // The stored registry re-seeds the single Chat server when it is empty, so
    // "no active server" is only a transient state; the destination is still
    // that server's sign-in, never a backend chooser or a setup wizard.
    test('no active server goes to authentication, never a chooser', () {
      final read = _reader(
        activeServer: const AsyncData(null),
        auth: AuthNavigationState.needsLogin,
      );

      check(resolveRouteRedirect(Routes.chat, read))
          .equals(Routes.authentication);
      check(resolveRouteRedirect(Routes.splash, read))
          .equals(Routes.authentication);
      check(resolveRouteRedirect(Routes.profile, read))
          .equals(Routes.authentication);
      // An auth route is left alone.
      check(resolveRouteRedirect(Routes.authentication, read)).isNull();
    });

    test('a loading session holds the splash', () {
      final read = _reader(auth: AuthNavigationState.loading);

      check(resolveRouteRedirect(Routes.chat, read)).equals(Routes.splash);
      check(resolveRouteRedirect(Routes.splash, read)).isNull();
    });

    test('a recoverable auth error shows the connection issue page', () {
      final read = _reader(auth: AuthNavigationState.error);

      check(resolveRouteRedirect(Routes.chat, read))
          .equals(Routes.connectionIssue);
      check(resolveRouteRedirect(Routes.connectionIssue, read)).isNull();
    });

    test('a stale apiKey error sends an explicit auth flow to authentication',
        () {
      final read = _reader(
        authSnapshot: const AuthState(
          status: AuthStatus.error,
          error: 'apiKey is missing',
        ),
      );

      check(resolveRouteRedirect(Routes.chat, read))
          .equals(Routes.authentication);
    });

    test(
      'a refresh of the active server keeps the user where they are',
      () async {
        // Saving one of its addresses, or moving to another, fetches it again.
        final read = _reader(activeServer: await _refreshing(_server));

        check(resolveRouteRedirect(Routes.profile, read)).isNull();
        check(resolveRouteRedirect(Routes.chat, read)).isNull();
      },
    );

    test('a failed or loading server lookup does not strand the user', () {
      final failed = _reader(
        activeServer: AsyncError<ServerConfig?>('boom', StackTrace.empty),
        auth: AuthNavigationState.needsLogin,
      );
      final loading = _reader(
        activeServer: const AsyncLoading(),
        auth: AuthNavigationState.needsLogin,
      );

      check(resolveRouteRedirect(Routes.chat, failed))
          .equals(Routes.connectionIssue);
      check(resolveRouteRedirect(Routes.chat, loading)).equals(Routes.splash);
      check(resolveRouteRedirect(Routes.authentication, loading)).isNull();
    });
  });
}
