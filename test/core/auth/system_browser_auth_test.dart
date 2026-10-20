import 'package:conduit/core/auth/system_browser_auth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final jwt = '${'a' * 20}.${'b' * 40}.${'c' * 40}';

  group('ssoTokenFromNativeCookies', () {
    test('returns a valid JWT token cookie', () {
      expect(ssoTokenFromNativeCookies({'token': jwt}), jwt);
    });

    test('ignores missing, empty and placeholder values', () {
      expect(ssoTokenFromNativeCookies({}), isNull);
      expect(ssoTokenFromNativeCookies({'token': ''}), isNull);
      expect(ssoTokenFromNativeCookies({'token': '   '}), isNull);
      expect(ssoTokenFromNativeCookies({'token': 'null'}), isNull);
      expect(ssoTokenFromNativeCookies({'token': 'undefined'}), isNull);
      expect(ssoTokenFromNativeCookies({'token': 'a.b.c'}), isNull);
    });

    test('ignores values that are not the token cookie', () {
      expect(ssoTokenFromNativeCookies({'other': jwt}), isNull);
    });
  });

  group('systemBrowserAuthOutcomeFromNative', () {
    test('maps the native completion strings', () {
      expect(
        systemBrowserAuthOutcomeFromNative('done'),
        SystemBrowserAuthOutcome.done,
      );
      expect(
        systemBrowserAuthOutcomeFromNative('cancelled'),
        SystemBrowserAuthOutcome.cancelled,
      );
      expect(
        systemBrowserAuthOutcomeFromNative('error'),
        SystemBrowserAuthOutcome.failed,
      );
      expect(
        systemBrowserAuthOutcomeFromNative(null),
        SystemBrowserAuthOutcome.failed,
      );
    });
  });
}
