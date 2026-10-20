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
    // Scheme propio que el flujo nunca alcanza: la hoja queda abierta durante el
    // login y Dart la cierra (cancel) al ver la cookie token. Con "https" la sesión
    // se completaba en el primer redirect (Keycloak) y Dani no llegaba a escribir
    // (medido 20-10 en su iPhone, build 1956).
    let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "com.morenoibanez.chat") { _, error in
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
