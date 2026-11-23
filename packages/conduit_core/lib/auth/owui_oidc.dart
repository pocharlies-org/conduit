/// The host's OpenID Connect endpoints, as a type.
///
/// The core names what a sign-in flow is configured with; the URLs themselves
/// belong to the host (OWU-157): the home build's `live` config lives in
/// `packages/conduit_home`.
final class OwuiOidcConfig {
  const OwuiOidcConfig({
    required this.baseUrl,
    required this.keycloakRealmUrl,
    required this.clientId,
    required this.redirectUri,
    required this.scopes,
  });

  /// The Open WebUI the app talks to.
  final String baseUrl;

  /// The identity provider's realm.
  final String keycloakRealmUrl;

  /// Public client with PKCE S256 and no secret. It serves the SwiftUI app
  /// and this one: the redirect URI is what tells them apart.
  final String clientId;

  final String redirectUri;

  /// No `groups`: the client does not have that scope assigned and asking for
  /// it fails the whole request (`invalid_scope`). The exchange audience is a
  /// scope too, assigned by Keycloak, so the app does not ask.
  final String scopes;

  Uri authorizeUrl({required String challenge, required String state}) =>
      Uri.parse('$keycloakRealmUrl/protocol/openid-connect/auth').replace(
        queryParameters: <String, String>{
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': scopes,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'state': state,
        },
      );

  Uri get keycloakTokenUrl =>
      Uri.parse('$keycloakRealmUrl/protocol/openid-connect/token');

  /// The provider id in the path is Open WebUI's literal `oidc`.
  Uri get exchangeUrl => Uri.parse(
    '$baseUrl/api/v1/auths/oauth/oidc/token/exchange',
  );
}

/// What a completed sign-in yields: the Open WebUI JWT to send as bearer, and
/// the identity provider's refresh token that renews it later.
final class OwuiSignIn {
  const OwuiSignIn({required this.jwt, this.refreshToken});

  final String jwt;
  final String? refreshToken;
}

/// Login has to start again: the code or the refresh token no longer holds.
final class OwuiLoginException implements Exception {
  const OwuiLoginException(this.message);

  final String message;

  @override
  String toString() => message;
}
