import 'dart:convert';

import 'package:conduit_core/auth/owui_oidc.dart';
import 'package:dio/dio.dart';

/// The home build's OpenID Connect server: chat.e-dani.com behind the edani
/// realm (OWU-157). The core keeps the config type; the URL is the host's.
const homeOwuiConfig = OwuiOidcConfig(
  baseUrl: 'https://chat.e-dani.com',
  keycloakRealmUrl: 'https://auth-next.e-dani.com/realms/edani',
  clientId: 'openwebui-ios',
  redirectUri: 'com.morenoibanez.chat://auth/callback',
  scopes: 'openid email profile',
);

/// The tokens Keycloak answers with. Only [accessToken] and [refreshToken] are
/// kept: nothing else in the response is read.
final class OidcTokens {
  const OidcTokens({required this.accessToken, this.refreshToken});

  final String accessToken;
  final String? refreshToken;

  factory OidcTokens.fromJson(Map<String, dynamic> json) {
    final access = json['access_token'];
    if (access is! String || access.isEmpty) {
      throw const OwuiLoginException('Keycloak returned no access token');
    }
    final refresh = json['refresh_token'];
    return OidcTokens(
      accessToken: access,
      refreshToken: refresh is String && refresh.isNotEmpty ? refresh : null,
    );
  }
}

/// Keycloak and the Open WebUI token exchange, over a [Dio] with no
/// interceptors: neither request carries the Open WebUI bearer, and a 302 keeps
/// its meaning here (it is not a session-expiry signal).
final class OwuiOidc {
  OwuiOidc({required this.config, Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              followRedirects: false,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 30),
            ),
          );

  final OwuiOidcConfig config;
  final Dio _dio;

  /// Redeems the authorization [code] for Keycloak tokens.
  Future<OidcTokens> redeemCode({
    required String code,
    required String verifier,
  }) => _tokenRequest(<String, String>{
    'grant_type': 'authorization_code',
    'client_id': config.clientId,
    'code': code,
    'redirect_uri': config.redirectUri,
    'code_verifier': verifier,
  });

  /// Renews the Keycloak session without asking for the password again.
  Future<OidcTokens> refresh(String refreshToken) =>
      _tokenRequest(<String, String>{
        'grant_type': 'refresh_token',
        'client_id': config.clientId,
        'refresh_token': refreshToken,
      });

  /// Swaps the edani access token for the Open WebUI JWT the API accepts.
  ///
  /// The edani token travels only here, in the body. A 401/403 means the
  /// server will not accept it (unknown account, revoked, out of the 10/60 s
  /// rate limit): the caller sends the person back to the login instead of
  /// retrying blind.
  Future<String> exchangeForOwuiJwt(String accessToken) async {
    // A transport failure propagates as a DioException: it is not a verdict on
    // the token, and callers must not treat it as one.
    final response = await _dio.post<dynamic>(
      config.exchangeUrl.toString(),
      data: <String, dynamic>{'token': accessToken},
      options: Options(
        contentType: Headers.jsonContentType,
        validateStatus: (status) => status != null,
      ),
    );
    final status = response.statusCode ?? 0;
    if (status == 401 || status == 403) {
      throw const OwuiLoginException('token exchange refused');
    }
    if (status < 200 || status >= 300) {
      // Not a verdict on the token: a server that fails (or rate-limits) must
      // not cost the caller its refresh token.
      throw Exception('token exchange: HTTP $status');
    }
    final body = response.data;
    if (body is! Map) {
      throw const OwuiLoginException('token exchange returned no body');
    }
    final jwt = body['token'] ?? body['access_token'];
    if (jwt is! String || jwt.isEmpty) {
      throw const OwuiLoginException('token exchange returned no token');
    }
    return jwt;
  }

  Future<OidcTokens> _tokenRequest(Map<String, String> form) async {
    // See [exchangeForOwuiJwt]: only Keycloak's own answer is a verdict.
    final response = await _dio.post<dynamic>(
      config.keycloakTokenUrl.toString(),
      data: form,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (status) => status != null,
      ),
    );
    final status = response.statusCode ?? 0;
    if (status == 400 || status == 401) {
      // The code was used or expired, or the refresh token was revoked.
      throw const OwuiLoginException('keycloak rejected the request');
    }
    if (status < 200 || status >= 300) {
      // As above: only 400/401 say the token is done.
      throw Exception('keycloak token: HTTP $status');
    }
    final body = response.data;
    if (body is String) {
      return OidcTokens.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
    }
    if (body is Map<String, dynamic>) return OidcTokens.fromJson(body);
    throw const OwuiLoginException('keycloak returned no tokens');
  }
}
