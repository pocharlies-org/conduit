import 'package:conduit_core/auth/owui_oidc.dart';
import 'package:conduit_core/auth/pkce.dart';
import 'package:conduit/features/auth/views/authentication_page.dart';
import 'package:conduit/core/auth/system_browser_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PKCE', () {
    test('S256 matches the RFC 7636 appendix B vector', () {
      expect(
        s256Challenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk'),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('a generated verifier is RFC-valid and its challenge is S256', () {
      final pair = generatePkcePair();
      expect(pair.verifier.length, inInclusiveRange(43, 128));
      expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(pair.verifier), isTrue);
      expect(pair.challenge, s256Challenge(pair.verifier));
    });

    test('two attempts never share a verifier or a state', () {
      expect(generatePkcePair().verifier, isNot(generatePkcePair().verifier));
      expect(generatePkceState(), isNot(generatePkceState()));
    });
  });

  group('OwuiOidcConfig.live', () {
    test('authorize URL asks for the code with PKCE and the fixed callback', () {
      final url = OwuiOidcConfig.live.authorizeUrl(
        challenge: 'challenge',
        state: 'state',
      );
      expect(
        url.toString(),
        startsWith(
          '${OwuiOidcConfig.live.keycloakRealmUrl}/protocol/openid-connect/auth?',
        ),
      );
      expect(url.queryParameters, {
        'client_id': 'openwebui-ios',
        'redirect_uri': 'com.morenoibanez.chat://auth/callback',
        'response_type': 'code',
        'scope': 'openid email profile groups',
        'code_challenge': 'challenge',
        'code_challenge_method': 'S256',
        'state': 'state',
      });
      expect(
        OwuiOidcConfig.live.exchangeUrl.toString(),
        'https://chat.e-dani.com/api/v1/auths/oauth/oidc/token/exchange',
      );
    });
  });

  group('the callback the sheet hands back', () {
    const expectedState = 'the-state';
    Uri callback(Map<String, String> query) => Uri.parse(
      'com.morenoibanez.chat://auth/callback',
    ).replace(queryParameters: query);

    test('yields the code', () {
      expect(
        authorizationCodeFromCallback(
          callback({'code': 'the-code', 'state': expectedState}),
          expectedState: expectedState,
        ),
        'the-code',
      );
    });

    test("refuses another attempt's state", () {
      expect(
        () => authorizationCodeFromCallback(
          callback({'code': 'the-code', 'state': 'other'}),
          expectedState: expectedState,
        ),
        throwsA(isA<OwuiLoginException>()),
      );
    });

    test('refuses an error answer', () {
      expect(
        () => authorizationCodeFromCallback(
          callback({'error': 'access_denied', 'state': expectedState}),
          expectedState: expectedState,
        ),
        throwsA(isA<OwuiLoginException>()),
      );
    });

    test('refuses a missing code', () {
      expect(
        () => authorizationCodeFromCallback(
          callback({'state': expectedState}),
          expectedState: expectedState,
        ),
        throwsA(isA<OwuiLoginException>()),
      );
    });
  });

  group('the native sheet answer', () {
    test('a callback URL is a completed login', () {
      final result = systemBrowserAuthResultFromNative(
        'com.morenoibanez.chat://auth/callback?code=c&state=s',
      );
      expect(result.outcome, SystemBrowserAuthOutcome.done);
      expect(result.callbackUrl?.queryParameters['code'], 'c');
    });

    test('dismissal and failure are not a login', () {
      expect(
        systemBrowserAuthResultFromNative('cancelled').outcome,
        SystemBrowserAuthOutcome.cancelled,
      );
      for (final raw in [null, '', 'error', 'https://elsewhere.example/x']) {
        expect(
          systemBrowserAuthResultFromNative(raw).outcome,
          SystemBrowserAuthOutcome.failed,
        );
      }
    });
  });
}