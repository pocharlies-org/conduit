import AuthenticationServices
import Flutter
import UIKit

/// Presents the SSO login in the system browser sheet (ASWebAuthenticationSession):
/// AutoFill, one-time codes and password-manager extensions work there, and none of
/// them works in the in-app WebView (SC-2799). A non-ephemeral session lands its
/// cookies in `WKWebsiteDataStore.default()`, which is the store `CookieBridge` reads.
final class SystemBrowserAuthBridge: NSObject, ConduitBridge,
  ASWebAuthenticationPresentationContextProviding {
  static let shared = SystemBrowserAuthBridge()

  private var session: ASWebAuthenticationSession?
  private var host: ConduitBridgeHost?

  private override init() { super.init() }

  @MainActor func attach(to host: ConduitBridgeHost) {
    self.host = host
    let channel = FlutterMethodChannel(
      name: "com.conduit.app/system_browser_auth",
      binaryMessenger: host.messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "start":
        DispatchQueue.main.async { self?.start(call: call, result: result) }
      case "cancel":
        DispatchQueue.main.async {
          self?.session?.cancel()
          result(nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  @MainActor private func start(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let urlString = args["url"] as? String,
          let url = URL(string: urlString) else {
      result(FlutterError(code: "INVALID_ARGS", message: "Invalid URL", details: nil))
      return
    }
    session?.cancel()
    // The https callback (iOS 17.4+) closes the sheet when the OAuth flow returns to
    // the associated domain (AASA of chat.e-dani.com). On older iOS a never-matching
    // custom scheme is used and Dart closes the sheet once it sees the session cookie.
    let callbackScheme: String
    if #available(iOS 17.4, *) {
      callbackScheme = "https"
    } else {
      callbackScheme = "com.morenoibanez.chat"
    }
    let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { _, error in
      self.session = nil
      if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
        result("cancelled")
      } else if error != nil {
        result("error")
      } else {
        result("done")
      }
    }
    session.prefersEphemeralWebBrowserSession = false
    session.presentationContextProvider = self
    self.session = session
    // start()/presentationAnchor son la API válida desde iOS 12 (deprecada en
    // 17.4 pero funcional): el despliegue del Runner es iOS 16.
    if !session.start() {
      self.session = nil
      result("error")
    }
  }

  func presentationAnchor(for session: ASWebAuthenticationSession) -> UIWindow {
    // shortcut: sin escena activa no hay ancla real; la app está en primer
    // plano siempre que se abre la hoja, si falta un ancla viable se revisa.
    host?.activeWindowScene?.keyWindow ?? UIWindow()
  }
}
