import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// How a system-browser login ended.
enum SystemBrowserAuthOutcome {
  /// The page navigated to the app's callback scheme.
  done,

  /// The person dismissed the sheet.
  cancelled,

  /// The sheet could not complete (no platform, native failure).
  failed,
}

/// What the sheet answered: an outcome, and on [outcome] done the callback URL
/// it closed on.
final class SystemBrowserAuthResult {
  const SystemBrowserAuthResult._(this.outcome, this.callbackUrl);

  const SystemBrowserAuthResult.cancelled()
    : outcome = SystemBrowserAuthOutcome.cancelled,
      callbackUrl = null;

  const SystemBrowserAuthResult.failed()
    : outcome = SystemBrowserAuthOutcome.failed,
      callbackUrl = null;

  final SystemBrowserAuthOutcome outcome;
  final Uri? callbackUrl;
}

/// Maps the native bridge string to a result.
///
/// The native side answers either the callback URL's absolute string (the
/// sheet closed on our scheme) or `cancelled`/`error`. Pure, so the mapping is
/// unit-testable without a platform.
SystemBrowserAuthResult systemBrowserAuthResultFromNative(String? raw) {
  if (raw == null || raw.isEmpty) return const SystemBrowserAuthResult.failed();
  if (raw == 'cancelled') return const SystemBrowserAuthResult.cancelled();
  final callback = Uri.tryParse(raw);
  if (callback == null || callback.scheme != SystemBrowserAuth.callbackScheme) {
    return const SystemBrowserAuthResult.failed();
  }
  return SystemBrowserAuthResult._(SystemBrowserAuthOutcome.done, callback);
}

/// The system-browser sheet (`ASWebAuthenticationSession`) that runs the
/// Keycloak login.
///
/// A sheet and not a WebView: Google refuses embedded WebViews, and the sheet
/// is where the person's saved sessions and AutoFill live. The sheet closes
/// itself when the page lands on [callbackScheme] and hands that URL back;
/// the caller reads `code` and `state` from it.
class SystemBrowserAuth {
  static const callbackScheme = 'com.morenoibanez.chat';
  static const _channel = MethodChannel('com.conduit.app/system_browser_auth');

  /// The shell is iOS-only; other platforms have no Keycloak sheet.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static Future<SystemBrowserAuthResult> start(String url) async {
    try {
      final raw = await _channel.invokeMethod<String>('start', {'url': url});
      return systemBrowserAuthResultFromNative(raw);
    } on PlatformException {
      return const SystemBrowserAuthResult.failed();
    } on MissingPluginException {
      return const SystemBrowserAuthResult.failed();
    }
  }
}