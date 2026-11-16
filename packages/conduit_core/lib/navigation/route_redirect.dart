import 'package:conduit_core/auth/auth_state_manager.dart';
import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart';
import 'package:conduit_core/features/workspace/providers/workspace_capabilities_provider.dart';
import 'package:conduit_core/navigation/routes.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:riverpod/misc.dart';
import 'package:riverpod/riverpod.dart';

/// Reads a provider without listening: `Ref.read`, `WidgetRef.read` and
/// `ProviderContainer.read` all fit.
typedef ProviderRead = T Function<T>(ProviderListenable<T> provider);

/// The providers [resolveRouteRedirect] depends on. A host re-evaluates its
/// redirect whenever one of them changes.
final List<ProviderListenable<Object?>> routeRedirectDependencies = [
  reviewerModeProvider,
  activeServerProvider,
  authNavigationStateProvider,
  workspaceCapabilitiesProvider,
];

/// Where the app should send a user who asked for [location], or null to let
/// them stay.
///
/// The router's redirect policy, kept here so it is tested without
/// go_router or Flutter.
///
/// OWU-134: the app is Open WebUI only, pre-configured with the single seeded
/// server. There is no backend chooser, no setup wizard and no account
/// chooser: the splash hands over to the login of the active server when a
/// sign-in is owed, and to chat once there is a session.
String? resolveRouteRedirect(String location, ProviderRead read) {
  final reviewerMode = read(reviewerModeProvider);
  if (reviewerMode) {
    // Stay on whatever route if already in chat; otherwise go to chat.
    if (location == Routes.chat) return null;
    return Routes.chat;
  }

  final activeServerAsync = read(activeServerProvider);
  final authState = read(authNavigationStateProvider);

  // A stale optional Open WebUI credential must not block an explicit
  // authentication/recovery flow.
  final authSnapshot = read(authStateManagerProvider)
      .maybeWhen(data: (s) => s, orElse: () => null);
  if (!isAuthLocation(location) &&
      authSnapshot?.error?.contains('apiKey') == true) {
    return Routes.authentication;
  }

  // Authentication is authoritative even while the selected server provider
  // is refreshing or recovering from a transient storage error. Do not let a
  // completed sign-in be stranded on a sign-in page.
  if (authState == AuthNavigationState.authenticated &&
      isAuthLocation(location) &&
      location != Routes.connectionIssue) {
    return Routes.chat;
  }

  // A refresh of the server already known keeps the user where they are:
  // re-reading its addresses, or moving to another of them, does not change
  // whose app this is, and an account change shows its own loading through
  // auth. Only a first lookup holds the splash.
  if (activeServerAsync.isLoading && !activeServerAsync.hasValue) {
    // Avoid redirect loops: do not override explicit auth routes while loading
    if (isAuthLocation(location)) return null;
    // Keep splash during server loading otherwise
    return location == Routes.splash ? null : Routes.splash;
  }

  if (activeServerAsync.hasError) {
    // A failed read of the active server can be a moment's thing, as the
    // Keychain can be locked; auth routes stay open through it.
    if (isAuthLocation(location)) return null;
    return location == Routes.connectionIssue ? null : Routes.connectionIssue;
  }

  final hasActiveServer = activeServerAsync.value != null;

  if (!hasActiveServer) {
    // OWU-134: the stored registry re-seeds the single Chat server when it is
    // empty, so this is only a transient state (a wipe still being re-seeded).
    // The login of that server is the only destination there is.
    if (isAuthLocation(location)) return null;
    return Routes.authentication;
  }

  switch (authState) {
    case AuthNavigationState.loading:
      // Keep user on auth routes while loading to prevent bounce
      if (isAuthLocation(location)) return null;
      // Otherwise keep splash during session establishment
      return location == Routes.splash ? null : Routes.splash;
    case AuthNavigationState.needsLogin:
      if (location == Routes.connectionIssue) return null;
      // Redirect to authentication page if not already on an auth route.
      // This handles the post-logout case: sign-in for the same server, not
      // server setup.
      if (isAuthLocation(location)) return null;
      return Routes.authentication;
    case AuthNavigationState.error:
      final authSnapshot = read(authStateManagerProvider)
          .maybeWhen(data: (state) => state, orElse: () => null);
      final hasValidToken = authSnapshot?.hasValidToken ?? false;
      final isAuthFormRoute = isAuthLocation(location);
      if (!hasValidToken && isAuthFormRoute) {
        // Keep user on the login/authentication flow to show inline errors
        return null;
      }
      // Otherwise show connection issue page for recoverable auth errors
      return location == Routes.connectionIssue ? null : Routes.connectionIssue;
    case AuthNavigationState.authenticated:
      // Avoid unnecessary redirects if already on a non-auth route
      if (isAuthLocation(location) ||
          location == Routes.splash ||
          location == Routes.connectionIssue) {
        return Routes.chat;
      }
      return _workspaceRedirect(location, read);
  }
}

String? _workspaceRedirect(String location, ProviderRead read) {
  if (location != Routes.workspace &&
      !location.startsWith('${Routes.workspace}/')) {
    return null;
  }

  final capabilities = read(workspaceCapabilitiesProvider);
  // Fail closed in the page gate while permissions are loading or errored.
  if (!capabilities.hasValue) return null;

  final permitted = permittedWorkspaceSections(capabilities.requireValue);
  if (permitted.isEmpty) {
    return location == Routes.workspace ? null : Routes.workspace;
  }

  if (location == Routes.workspace) return permitted.first.path;
  final requested = workspaceSectionForPath(location);
  if (requested == null || !permitted.contains(requested)) {
    return permitted.first.path;
  }
  return null;
}

bool isAuthLocation(String location) {
  return location == Routes.authentication ||
      location == Routes.connectionIssue;
}
