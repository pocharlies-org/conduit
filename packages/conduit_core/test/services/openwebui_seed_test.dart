import 'package:checks/checks.dart';
import 'package:conduit_core/services/openwebui_seed.dart';
import 'package:test/test.dart';

void main() {
  group('OpenWebUiSeed.registryFromSeed (OWU-104)', () {
    tearDown(() => OpenWebUiSeed.installLoader(() async => '{}'));

    test('builds a server and a sessionless account per entry', () async {
      OpenWebUiSeed.installLoader(
        () async =>
            '{"servers":[{"name":"Chat","url":"https://chat.e-dani.com"},'
            '{"url":"https://otro.example:8443"}]}',
      );
      final registry = await OpenWebUiSeed.registryFromSeed();
      check(registry).isNotNull();
      final servers = registry!.servers;
      check(servers.length).equals(2);
      check(servers.first.id).equals('chat-e-dani-com');
      check(servers.first.name).equals('Chat');
      check(servers.first.endpoints.single.url)
          .equals('https://chat.e-dani.com');
      check(servers[1].name).equals('otro.example');
      check(registry.accounts.length).equals(2);
      check(registry.accounts.first.serverId).equals(servers.first.id);
      check(registry.accounts.first.userId).isNull();
    });

    test('nothing to seed when the asset is absent or malformed', () async {
      OpenWebUiSeed.installLoader(() => throw StateError('missing asset'));
      check(await OpenWebUiSeed.registryFromSeed()).isNull();
      OpenWebUiSeed.installLoader(() async => 'no es json');
      check(await OpenWebUiSeed.registryFromSeed()).isNull();
      OpenWebUiSeed.installLoader(() async => '{"servers":[]}');
      check(await OpenWebUiSeed.registryFromSeed()).isNull();
      OpenWebUiSeed.installLoader(
        () async => '{"servers":[{"url":"sin-esquema"}]}',
      );
      check(await OpenWebUiSeed.registryFromSeed()).isNull();
    });
  });
}
