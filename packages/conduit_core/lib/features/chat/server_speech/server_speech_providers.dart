import 'package:riverpod/riverpod.dart';

import 'package:conduit_core/providers/app_providers.dart';

import 'openwebui_server_speech.dart';
import 'server_speech.dart';

/// Speech for the selected model's backend, or null when it has none.
///
/// OWU-134: every model belongs to the Open WebUI server; without its speech
/// the device engines are used.
final serverSpeechProviderProvider = Provider<ServerSpeechProvider?>((ref) {
  final api = ref.watch(apiServiceProvider);
  return api == null ? null : OpenWebUiServerSpeech(api);
});
