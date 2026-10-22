import AuthenticationServices
import Flutter
import UIKit
import WebKit

/// Presents the SSO login full-screen (SC-2799, Dani 21-10: la hoja de
/// `ASWebAuthenticationSession` pinta barra de título y toolbar — «MUY feo», y
/// el navegador del sistema no tiene API para ocultarlas). El `WKWebView` a
/// pantalla completa con el almacén de datos por defecto mantiene lo que
/// importa: AutoFill de contraseñas y códigos de un solo uso funcionan también
/// aquí (extensión AutoFill del sistema, iOS 12+), y sus cookies caen en
/// `WKWebsiteDataStore.default()`, que es lo que lee `CookieBridge`.
///
/// El modo por defecto es la hoja del sistema (`sheet`): es donde Google OAuth
/// funciona — rechaza WebViews embebidas (`disallowed_useragent`) — y donde
/// viven la sesión de Google y AutoFill (OWU-107, Dani 22-10: «antes funcionaba
/// y ahora ya no va»). La pantalla completa dentro de la app queda como
/// opción desde el estado de error.
final class SystemBrowserAuthBridge: NSObject, ConduitBridge,
  ASWebAuthenticationPresentationContextProviding {
  static let shared = SystemBrowserAuthBridge()

  private var session: ASWebAuthenticationSession?
  private var controller: SSOWebController?
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
          self?.controller?.finish("done")
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
    controller?.finish("cancelled")
    if (args["fullScreen"] as? Bool) == true {
      startFullScreen(url: url, result: result)
    } else {
      startSheet(url: url, result: result)
    }
  }

  private func startFullScreen(url: URL, result: @escaping FlutterResult) {
    let controller = SSOWebController(url: url)
    controller.onDismiss = { outcome in result(outcome) }
    self.controller = controller
    guard let anchor = host?.activeWindowScene?.keyWindow?.rootViewController else {
      self.controller = nil
      result("error")
      return
    }
    anchor.present(controller, animated: true)
  }

  private func startSheet(url: URL, result: @escaping FlutterResult) {
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

/// Pantalla completa sin cromo de navegador: solo la web y una X para salir.
/// El flujo nunca "completa" por sí solo: Dart cierra la pantalla (cancel) al
/// ver la cookie `token`.
private final class SSOWebController: UIViewController, WKNavigationDelegate {
  var onDismiss: ((String) -> Void)?

  private let url: URL
  private var finished = false

  init(url: URL) {
    self.url = url
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .fullScreen
  }

  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black

    // Sin configuration: almacén de datos por defecto → cookies visibles para CookieBridge.
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    webView.navigationDelegate = self
    webView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(webView)

    let close = UIButton(type: .system)
    close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
    close.tintColor = UIColor.white.withAlphaComponent(0.7)
    close.accessibilityLabel = "Cerrar"
    close.addTarget(self, action: #selector(userClosed), for: .touchUpInside)
    close.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(close)

    NSLayoutConstraint.activate([
      webView.topAnchor.constraint(equalTo: view.topAnchor),
      webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      close.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
      close.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
      close.widthAnchor.constraint(equalToConstant: 30),
      close.heightAnchor.constraint(equalToConstant: 30),
    ])

    webView.load(URLRequest(url: url))
  }

  @objc private func userClosed() { finish("cancelled") }

  /// Un solo disparo: el resultado de `start` no puede emitirse dos veces.
  func finish(_ outcome: String) {
    guard !finished else { return }
    finished = true
    onDismiss?(outcome)
    if presentingViewController != nil {
      dismiss(animated: true)
    }
  }
}
