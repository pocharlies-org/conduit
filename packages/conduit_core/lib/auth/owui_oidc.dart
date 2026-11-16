import 'dart:convert';

import 'package:dio/dio.dart';

/// The product's fixed OpenID Connect endpoints (ARCHITECTURE.md).
///
/// One server, one realm: nothing here comes from the user or the network.
final class OwuiOidcConfig {
  const OwuiOidcConfig({
    required this.baseUrl,
    required this.keycloakRealmUrl,
    required this.clientId,
    required this.redirectUri,
    required this.scopes,
  });

  /// `chat.e-dani.com`: the Open WebUI the app talks to.
  final String baseUrl;

  /// `https://auth-next.e-dani.com/realms/edani`.
  final String keycloakRealmUrl;

  /// Public client with PKCE S256 and no secret. It serves the SwiftUI app and
  /// this one: the redirect URI is what tells them apart.
  final String clientId;

  final String redirectUri;

  /// No `groups`: the client does not have that scope assigned and asking for
  /// it fails the whole request (`invalid_scope`). The `openwebui-ios-exchange`
  /// audience is a scope too, assigned by Keycloak, so the app does not ask.
  final String scopes;

  static const live = OwuiOidcConfig(
    baseUrl: 'https://chat.e-dani.com',
    keycloakRealmUrl: 'https://auth-next.e-dani.com/realms/edani',
    clientId: 'openwebui-ios',
    redirectUri: 'com.morenoibanez.chat://auth/callback',
    scopes: 'openid email profile',
  );

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

  /// The provider id in the path is Open WebUI's literal `oidc`, not `edani`.
  Uri get exchangeUrl => Uri.parse(
    '$baseUrl/api/v1/auths/oauth/oidc/token/exchange',
  );
}

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

/// Login has to start again: the code or the refresh token no longer holds.
final class OwuiLoginException implements Exception {
  const OwuiLoginException(this.message);

  final String message;

  @override
  String toString() => message;
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
      throw OwuiLoginException('token exchange: HTTP $status');
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
      throw OwuiLoginException('keycloak token: HTTP $status');
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