import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Outcome of a system-browser SSO sheet, mapped from the native bridge string.
enum SystemBrowserAuthOutcome { done, cancelled, failed }

/// Maps the native completion string to an [SystemBrowserAuthOutcome].
///
/// Pure so the polling loop's decision is unit-testable without a platform.
SystemBrowserAuthOutcome systemBrowserAuthOutcomeFromNative(String? raw) {
  switch (raw) {
    case 'done':
      return SystemBrowserAuthOutcome.done;
    case 'cancelled':
      return SystemBrowserAuthOutcome.cancelled;
    default:
      return SystemBrowserAuthOutcome.failed;
  }
}

/// Extracts the Open WebUI session token from native cookies, or null.
///
/// The token cookie holds a JWT: three dot-separated segments, at least 50
/// chars. This filters out `null`/`undefined`/empty placeholders the frontend
/// may leave before OAuth completes. Pure and host-agnostic for testing.
String? ssoTokenFromNativeCookies(Map<String, String> cookies) {
  final value = cookies['token']?.trim();
  if (value == null || value.isEmpty) return null;
  if (value == 'null' || value == 'undefined') return null;
  if (value.split('.').length != 3 || value.length < 50) return null;
  return value;
}

/// Presents the SSO login on iOS, two ways (SC-2799):
///
/// - [fullScreen] (Keycloak SSO): an in-app `WKWebView` with no browser chrome
///   — the system sheet paints a title bar and toolbar, which Dani rejected
///   (21-10, «MUY feo»). AutoFill and one-time codes work here too (system
///   AutoFill extension).
/// - default (proxy login): the system-browser sheet
///   (`ASWebAuthenticationSession`). Google OAuth rejects embedded WebViews
///   (`disallowed_useragent`), so that flow needs the real browser.
///
/// Both are non-ephemeral: their cookies land in the shared
/// `WKWebsiteDataStore` that [NativeCookieManager] reads. The caller opens the
/// screen and polls that store for the session token, then calls [cancel].
class SystemBrowserAuth {
  static const _channel = MethodChannel('com.conduit.app/system_browser_auth');

  /// The system-browser sheet is iOS-only; Android keeps the WebView flow.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Opens the login at [url]. Resolves when it closes: on the OAuth redirect
  /// ([SystemBrowserAuthOutcome.done]), the user dismissing it
  /// ([SystemBrowserAuthOutcome.cancelled]) or a native failure. With
  /// [fullScreen] the login is an in-app WebView without browser chrome.
  static Future<SystemBrowserAuthOutcome> start(String url,
      {bool fullScreen = false}) async {
    try {
      final raw = await _channel.invokeMethod<String>('start',
          {'url': url, 'fullScreen': fullScreen});
      return systemBrowserAuthOutcomeFromNative(raw);
    } on PlatformException {
      return SystemBrowserAuthOutcome.failed;
    } on MissingPluginException {
      return SystemBrowserAuthOutcome.failed;
    }
  }

  /// Closes the sheet once the session token is detected by polling.
  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on PlatformException {
      // Already dismissed — nothing to do.
    } on MissingPluginException {
      // Not iOS — nothing to dismiss.
    }
  }
}
