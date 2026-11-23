import 'package:conduit_core/services/optimized_storage_service.dart';

import 'owui_oidc.dart';
import 'package:conduit_core/utils/debug_logger.dart';

/// Renews one Open WebUI session without asking for the password again.
///
/// The Open WebUI JWT is what the API accepts as bearer, and it expires. The
/// durable half of the session is Keycloak's refresh token, filed under the
/// Open WebUI user it belongs to: renewing mints a new Keycloak access token,
/// the token exchange turns it into a new JWT, and that JWT replaces the
/// stored one. No password, no browser sheet.
///
/// Only a definitive rejection (400/401 from Keycloak, 401/403 from the
/// exchange) drops the refresh token: a network failure leaves it in place,
/// because signing the person out over a bad minute of coverage is worse than
/// failing this one request.
final class SessionRefresher {
  SessionRefresher({
    required this.storage,
    required this.oidc,
    required this.userId,
    required this.stillCurrent,
  });

  final OptimizedStorageService storage;
  final OwuiOidc oidc;
  final String userId;

  /// Whether this user is still the signed-in one. Checked before the renewed
  /// JWT is stored, so a renewal that lands after a sign-out (or an account
  /// switch) cannot resurrect a session.
  final bool Function() stillCurrent;

  Future<String?>? _inFlight;

  /// One renewal at a time per refresher: parallel requests that hit an
  /// expired session share the same refresh instead of racing for it.
  Future<String?> refreshOnce() =>
      _inFlight ??= _refresh().whenComplete(() => _inFlight = null);

  Future<String?> _refresh() async {
    final String? refreshToken;
    try {
      refreshToken = await storage.getRefreshToken(userId);
    } catch (error) {
      DebugLogger.error(
        'refresh-token-read-failed',
        scope: 'auth/refresh',
        error: error,
      );
      return null;
    }
    if (refreshToken == null || refreshToken.isEmpty) return null;

    final String jwt;
    final OidcTokens tokens;
    try {
      tokens = await oidc.refresh(refreshToken);
      jwt = await oidc.exchangeForOwuiJwt(tokens.accessToken);
    } on OwuiLoginException catch (error) {
      // Revoked or expired: only a fresh login gets a working session.
      DebugLogger.auth('session refresh refused: $error');
      await _forgetRefreshToken();
      return null;
    } catch (error) {
      // Transport failure: keep the refresh token for the next attempt.
      DebugLogger.warning('session refresh failed: $error', scope: 'auth/refresh');
      return null;
    }

    if (!stillCurrent()) return null;

    if (tokens.refreshToken case final rotated? when rotated != refreshToken) {
      await storage.saveRefreshToken(userId, rotated);
    }
    final applied = await storage.saveAuthTokenIfCurrent(
      jwt,
      canCommit: stillCurrent,
    );
    return applied ? jwt : null;
  }

  Future<void> _forgetRefreshToken() async {
    try {
      await storage.deleteRefreshToken(userId);
    } catch (error) {
      DebugLogger.error(
        'refresh-token-delete-failed',
        scope: 'auth/refresh',
        error: error,
      );
    }
  }
}