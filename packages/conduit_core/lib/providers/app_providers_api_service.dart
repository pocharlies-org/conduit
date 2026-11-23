part of 'app_providers.dart';

/// In-memory bearer mirror used when [apiServiceProvider] is rebuilt.
///
/// The API client watches transport configuration such as the incomplete-logout
/// Cookie fence and can therefore be replaced during authentication publication.
/// Keeping the current bearer in an independent process-local provider prevents
/// that replacement from reverting to an unauthenticated client. The token is
/// never persisted or logged here; secure credential storage remains owned by
/// [OptimizedStorageService].
final apiAuthTokenMirrorProvider =
    NotifierProvider<ApiAuthTokenMirror, String?>(ApiAuthTokenMirror.new);

final class ApiAuthTokenMirror extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? token) {
    if (state != token) state = token;
  }
}

// API Service provider with unified auth integration
final apiServiceProvider = Provider<ApiService?>((ref) {
  // If reviewer mode is enabled, skip creating ApiService
  final reviewerMode = ref.watch(reviewerModeProvider);
  if (reviewerMode) {
    return null;
  }
  final authToken = ref.watch(apiAuthTokenMirrorProvider);
  final activeServer = ref.watch(activeServerProvider);
  final workerManager = ref.watch(workerManagerProvider);
  final liveFence = ref.watch(incompleteLogoutFenceProvider);
  final suppressCookieHeader =
      liveFence ||
      ref.read(incompleteLogoutFenceProvider.notifier).desiredSuppressed;

  return activeServer.maybeWhen(
    data: (server) {
      if (server == null) return null;

      final apiService = ApiService(
        serverConfig: server,
        workerManager: workerManager,
        authToken: authToken,
        suppressCookieCustomHeader: suppressCookieHeader,
        // The active account's client on the route in use: a proxy turning
        // it away says that route's session there has expired.
        reportsRouteRefusals: true,
      );

      // One renewal at a time for this client: parallel requests sharing an
      // expired bearer share the refresh instead of racing for it.
      Future<String?>? renewing;
      Future<String?> renewSession() =>
          renewing ??= _renewOpenWebUiSession(ref).whenComplete(
            () => renewing = null,
          );

      // Keep callbacks in sync so interceptor can notify auth manager
      apiService.setAuthCallbacks(
        onSessionExpired: () async {
          final jwt = await renewSession();
          if (jwt == null) return false;
          // The interceptor holds this client's bearer: rotating it here is
          // what the replayed request will carry.
          apiService.updateAuthToken(jwt);
          return true;
        },
        onAuthTokenInvalid: () {
          // Called when auth errors occur (401/403)
          // Show connection issue page instead of logging out
          final authManager = ref.read(authStateManagerProvider.notifier);
          authManager.onAuthIssue();
        },
        onTokenInvalidated: () async {
          // Called for token expiry - attempt silent re-login
          final authManager = ref.read(authStateManagerProvider.notifier);
          await authManager.onTokenInvalidated();
        },
      );

      // Set up callback for unified auth state manager
      // (legacy properties kept during transition)
      apiService.onTokenInvalidated = () async {
        final authManager = ref.read(authStateManagerProvider.notifier);
        await authManager.onTokenInvalidated();
      };

      // Keep legacy callback for backward compatibility during transition
      apiService.onAuthTokenInvalid = () {
        // Show connection issue page instead of logging out
        final authManager = ref.read(authStateManagerProvider.notifier);
        authManager.onAuthIssue();
      };

      ref.onDispose(apiService.dispose);
      return apiService;
    },
    orElse: () => null,
  );
});

/// One renewal of the active session through Keycloak's refresh token.
///
/// Keyed by the Open WebUI user the session belongs to: the refresh token is
/// filed under that id, so a renewal can never mint a JWT for a different
/// account than the one signed in.
Future<String?> _renewOpenWebUiSession(Ref ref) {
  // The host's identity provider renews (OWU-157); a build without one keeps
  // the session until it expires and the sign-in screen takes over.
  return ref.read(sessionRenewalProvider)?.call(ref) ??
      Future<String?>.value();
}

/// Whether server-backed Open WebUI settings are usable in the current
/// session. A retained server or API object after sign-out is not sufficient.
final openWebUiAccountAvailableProvider = Provider<bool>((ref) {
  return ref.watch(apiServiceProvider) != null &&
      ref.watch(isAuthenticatedProvider2);
});

// Socket.IO service provider
/// Monotonic identity for one OpenWebUI authentication session.
///
/// API and database objects are intentionally stable across logout on the same
/// server. Their identity therefore cannot distinguish user A's late async work
/// from a later user B session. Rebuilding this object on every auth-state
/// transition gives all server-bound work an ABA-safe ownership boundary.
final openWebUiAuthSessionEpochProvider = Provider<Object>((ref) {
  ref.watch(isAuthenticatedProvider2);
  ref.watch(authTokenProvider3);
  ref.watch(currentUserProvider2.select((user) => user?.id));
  return Object();
});
