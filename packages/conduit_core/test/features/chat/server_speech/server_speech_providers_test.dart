import 'package:checks/checks.dart';
import 'package:conduit_core/features/chat/server_speech/openwebui_server_speech.dart';
import 'package:conduit_core/features/chat/server_speech/server_speech_providers.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

void main() {
  ApiService openWebUi() => ApiService(
    serverConfig: const ServerConfig(
      id: 'server',
      name: 'Server',
      url: 'https://owui.example',
    ),
    workerManager: WorkerManager(),
  );

  group('serverSpeechProvider', () {
    test('an Open WebUI model uses its server', () {
      final c = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(openWebUi())],
      );
      addTearDown(c.dispose);

      check(c.read(serverSpeechProviderProvider)).isA<OpenWebUiServerSpeech>();
    });

    test('without an API there is no server speech', () {
      final c = ProviderContainer(
        overrides: [apiServiceProvider.overrideWithValue(null)],
      );
      addTearDown(c.dispose);

      check(c.read(serverSpeechProviderProvider)).isNull();
    });
  });
}
