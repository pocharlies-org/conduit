import 'package:conduit_core/features/auth/providers/unified_auth_providers.dart'
    show currentUserProvider2;
import 'package:conduit_core/providers/app_providers.dart'
    show optimizedStorageServiceProvider;
import 'package:riverpod/riverpod.dart';

import 'owui_oidc.dart';
import 'session_refresher.dart';

/// One renewal of the active session through Keycloak's refresh token (OWU-157).
///
/// Keyed by the Open WebUI user the session belongs to: the refresh token is
/// filed under that id, so a renewal can never mint a JWT for a different
/// account than the one signed in.
Future<String?> renewHomeSession(Ref ref) async {
  final userId = ref.read(currentUserProvider2)?.id;
  if (userId == null) return null;
  return SessionRefresher(
    storage: ref.read(optimizedStorageServiceProvider),
    oidc: OwuiOidc(config: homeOwuiConfig),
    userId: userId,
    stillCurrent: () => ref.read(currentUserProvider2)?.id == userId,
  ).refreshOnce();
}
