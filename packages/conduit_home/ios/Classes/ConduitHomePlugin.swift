import Flutter

/// Registra la hoja del navegador del sistema que usa el login de casa.
///
/// El puente vivía en el Runner; OWU-157 lo trajo al paquete para que un
/// build genérico, sin `conduit_home`, no lleve el sheet Keycloak.
public final class ConduitHomePlugin: NSObject, FlutterPlugin {
  // El registrar no retiene el handler: sin esto el puente muere tras
  // `register` y el canal responde `nil` a `start`.
  private static var bridges: [SystemBrowserAuthBridge] = []

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "com.conduit.app/system_browser_auth",
      binaryMessenger: registrar.messenger()
    )
    let bridge = SystemBrowserAuthBridge()
    bridges.append(bridge)
    bridge.attach(to: channel)
  }
}
