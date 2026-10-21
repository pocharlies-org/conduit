import 'dart:convert';

import '../models/openwebui_registry.dart';

/// Cuentas precargadas (OWU-104): el `assets/seed_accounts.json` del build se
/// escribe en el registry en el primer arranque, cuando nunca hubo nada
/// guardado — las cuentas se configuran desde fuera del teléfono, no añadiendo
/// desde Ajustes. Tras un wipe el registry queda guardado (vacío) y no vuelve
/// a sembrar.
///
/// Formato: `{"servers":[{"name":"Chat","url":"https://chat.e-dani.com"}]}`.
class OpenWebUiSeed {
  OpenWebUiSeed._();

  static Future<String> Function()? _loader;

  /// Como `PreferencesStore.installLoader`: el host instala la lectura del
  /// asset (`rootBundle`) al arrancar.
  static void installLoader(Future<String> Function() loader) {
    _loader = loader;
  }

  /// Registry construido desde el seed, o null si no hay nada que sembrar:
  /// sin loader, asset ausente o mal formado, o sin servidores válidos.
  static Future<OpenWebUiRegistry?> registryFromSeed() async {
    final loader = _loader;
    if (loader == null) return null;
    final List<dynamic> servers;
    try {
      final decoded = jsonDecode(await loader()) as Map<String, dynamic>;
      servers = decoded['servers'] as List<dynamic>? ?? const [];
    } catch (_) {
      // Asset ausente o mal formado: nada que sembrar, nunca un fallo.
      return null;
    }
    final seededServers = <OpenWebUiServer>[];
    final seededAccounts = <OpenWebUiAccount>[];
    for (final item in servers) {
      if (item is! Map) continue;
      final url = item['url'] as String?;
      if (url == null) continue;
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || !uri.hasAuthority) continue;
      final name = (item['name'] as String?)?.trim();
      // shortcut: el id sale del host; dos servidores sembrados en el mismo
      // host colisionarían — el seed es una lista corta y a mano.
      final id = uri.host.replaceAll(RegExp(r'[^A-Za-z0-9]'), '-');
      seededServers.add(
        OpenWebUiServer(
          id: id,
          name: (name == null || name.isEmpty) ? uri.host : name,
          endpoints: [OpenWebUiEndpoint(id: '$id-route', url: url)],
        ),
      );
      // Cuenta sin userId: el primer login prueba quién es (el registry lo
      // registra entonces, como con cualquier cuenta recién firmada).
      seededAccounts.add(OpenWebUiAccount(id: id, serverId: id));
    }
    if (seededServers.isEmpty) return null;
    return OpenWebUiRegistry(servers: seededServers, accounts: seededAccounts);
  }
}
