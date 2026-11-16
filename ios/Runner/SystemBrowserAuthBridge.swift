import AuthenticationServices
import Flutter
import UIKit

/// La hoja del navegador del sistema para el login PKCE.
///
/// Hoja y no WebView: Google rechaza las WebViews embebidas
/// (`disallowed_useragent`) y en la hoja viven la sesión de Keycloak y AutoFill.
/// La hoja se cierra sola cuando la página navega al esquema propio de la app y
/// devuelve esa URL a Dart, que lee de ella `code` y `state`.
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
    // Un intento nuevo cancela el anterior: su completion llega como
    // `cancelled` y el de Dart ya no lo espera.
    session?.cancel()
    let session = ASWebAuthenticationSession(
      url: url,
      callbackURLScheme: "com.morenoibanez.chat"
    ) { callbackURL, error in
      self.session = nil
      if let error = error as? ASWebAuthenticationSessionError,
         error.code == .canceledLogin {
        result("cancelled")
      } else if error != nil {
        result("error")
      } else if let callbackURL = callbackURL {
        result(callbackURL.absoluteString)
      } else {
        result("error")
      }
    }
    // No efímera: la sesión de Keycloak (y la de Google dentro de ella) tiene
    // que sobrevivir entre aperturas.
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