import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The login sheet hands the callback back through a URL scheme, and a scheme
/// the app does not register never reaches it: `ASWebAuthenticationSession`
/// has no one to give the URL to and the sign-in fails with no reason.
/// OWU-134 went to TestFlight without the registration; this reads both files
/// so that cannot happen again.
void main() {
  test('the app registers the callback scheme the login sheet asks for', () {
    final bridge = File(
      'ios/Runner/SystemBrowserAuthBridge.swift',
    ).readAsStringSync();
    final scheme = RegExp(
      r'callbackURLScheme:\s*"([^"]+)"',
    ).firstMatch(bridge)?.group(1);
    expect(scheme, isNotNull, reason: 'the bridge declares no callback scheme');

    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    final registered = RegExp(
      r'<key>CFBundleURLSchemes</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).allMatches(plist).expand(
      (match) => RegExp(r'<string>([^<]+)</string>')
          .allMatches(match.group(1)!)
          .map((entry) => entry.group(1)!),
    );
    // A build setting is what release uses; the literal must be spelled out
    // here, since the sheet asks for it as a constant.
    expect(registered, contains(scheme));
  });
}