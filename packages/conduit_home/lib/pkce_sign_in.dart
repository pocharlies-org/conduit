import 'package:conduit_core/auth/owui_oidc.dart';
import 'package:conduit_core/auth/pkce.dart';

import 'owui_oidc.dart';
import 'system_browser_auth.dart';

/// Runs the login sheet, redeems the code and exchanges the edani token for
/// an Open WebUI JWT.
///
/// Null when the person dismissed the sheet; [OwuiLoginException] when the
/// server refused (the realm's error, another attempt's `state`, a code that
/// no longer holds, an exchange that answers 401/403).
Future<OwuiSignIn?> runPkceSignIn() async {
  final config = homeOwuiConfig;
  final pkce = generatePkcePair();
  final state = generatePkceState();
  final result = await SystemBrowserAuth.start(
    config.authorizeUrl(challenge: pkce.challenge, state: state).toString(),
  );
  if (result.outcome == SystemBrowserAuthOutcome.cancelled) return null;
  final callback = result.callbackUrl;
  if (result.outcome != SystemBrowserAuthOutcome.done || callback == null) {
    throw const OwuiLoginException('the login sheet failed');
  }
  final code = authorizationCodeFromCallback(
    callback,
    expectedState: state,
  );

  final oidc = OwuiOidc(config: config);
  final tokens = await oidc.redeemCode(code: code, verifier: pkce.verifier);
  // The edani access token ends here: what the app keeps, and sends as
  // bearer, is the Open WebUI JWT the exchange answers with.
  final jwt = await oidc.exchangeForOwuiJwt(tokens.accessToken);
  return OwuiSignIn(jwt: jwt, refreshToken: tokens.refreshToken);
}

/// The authorization code a callback URL carries, checked against the `state`
/// this attempt sent.
///
/// Keycloak answers errors on the same redirect, and an answer that carries
/// another attempt's state is not this one's: both are refusals, never a
/// session.
String authorizationCodeFromCallback(
  Uri callback, {
  required String expectedState,
}) {
  final error = callback.queryParameters['error'];
  if (error != null && error.isNotEmpty) {
    throw OwuiLoginException('authorization refused: $error');
  }
  if (callback.queryParameters['state'] != expectedState) {
    throw const OwuiLoginException('authorization answered another attempt');
  }
  final code = callback.queryParameters['code'];
  if (code == null || code.isEmpty) {
    throw const OwuiLoginException('authorization returned no code');
  }
  return code;
}