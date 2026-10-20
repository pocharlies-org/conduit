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

/// Presents the SSO login in the iOS system-browser sheet
/// (`ASWebAuthenticationSession`), where AutoFill, one-time codes and
/// password-manager extensions (1Password, KeePass) work — none of them do in
/// the in-app WebView (SC-2799).
///
/// The sheet is non-ephemeral, so its cookies land in the shared
/// `WKWebsiteDataStore` that [NativeCookieManager] reads. The caller opens the
/// sheet and polls that store for the session token, then calls [cancel].
class SystemBrowserAuth {
  static const _channel = MethodChannel('com.conduit.app/system_browser_auth');

  /// The system-browser sheet is iOS-only; Android keeps the WebView flow.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Opens the sheet at [url]. Resolves when it closes: on the OAuth redirect
  /// ([SystemBrowserAuthOutcome.done]), the user dismissing it
  /// ([SystemBrowserAuthOutcome.cancelled]) or a native failure.
  static Future<SystemBrowserAuthOutcome> start(String url) async {
    try {
      final raw = await _channel.invokeMethod<String>('start', {'url': url});
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
