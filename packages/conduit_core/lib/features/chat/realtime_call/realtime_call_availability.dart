import 'dart:async';

import 'package:riverpod/riverpod.dart';

import 'package:conduit_core/auth/token_validator.dart';
import 'package:conduit_core/models/model.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/services/server_tls_http_client_factory.dart';
import 'package:conduit_core/services/settings_service.dart';

import 'realtime_bridge_transport.dart';
import 'realtime_call_ports.dart';

/// Builds the device's realtime audio engine, or returns null on a host
/// without one; calls are then Standard.
final realtimePcmAudioFactoryProvider =
    Provider<RealtimePcmAudioPort? Function()>((ref) => () => null);

/// Finds the realtime voice for a call with a model; see
/// [resolveRealtimeCallRoute].
final realtimeCallRouteResolverProvider =
    Provider<
      Future<RealtimeCallRoute> Function(Model model, {bool newChat})
    >(
      (ref) =>
          (model, {newChat = false}) =>
              resolveRealtimeCallRoute(ref, model, newChat: newChat),
    );

/// Why a call runs as a Standard call instead of a realtime one.
enum RealtimeCallBlock {
  /// The user chose Standard calls.
  standardChosen,

  /// Temporary chats keep Standard calls.
  temporaryChat,

  /// The Open WebUI server has realtime calls off, or predates them.
  serverRealtimeOff,

  /// The account may not call, or its permissions could not be read.
  callNotPermitted,

  /// The account signed in with an API key, which realtime calls refuse.
  noSessionToken,
}

/// The voice a realtime call with a model would use, or why it has none: the
/// [bridge] of the Open WebUI server.
typedef RealtimeCallRoute = ({
  RealtimeBridgeTransport? bridge,
  RealtimeCallBlock? block,
});

RealtimeCallRoute _blocked(RealtimeCallBlock block) => (
  bridge: null,
  block: block,
);

/// Finds the realtime voice for a call with [model] in the open chat, or in
/// the new chat the call starts when [newChat]: Open WebUI's own when its
/// server offers one. Fails closed: anything unknown makes the call Standard.
Future<RealtimeCallRoute> resolveRealtimeCallRoute(
  Ref ref,
  Model model, {
  bool newChat = false,
}) async {
  if (ref.read(appSettingsProvider).voiceCallMode == VoiceCallMode.standard) {
    return _blocked(RealtimeCallBlock.standardChosen);
  }
  // A call that starts a new chat is not in the one open now, and the new
  // chat starts temporary as a new chat does: when the server enforces it, or
  // settings say so.
  final active = newChat ? null : ref.read(activeConversationProvider);
  final temporary = newChat
      ? ref.read(temporaryChatEnforcedProvider) ||
            ref.read(appSettingsProvider).temporaryChatByDefault
    : ref.read(temporaryChatEnabledProvider);
  if (temporary || (active != null && isTemporaryChat(active.id))) {
    return _blocked(RealtimeCallBlock.temporaryChat);
  }

  final config = ref.read(backendConfigProvider).value;
  if (config?.enableRealtimeCall != true) {
    return _blocked(RealtimeCallBlock.serverRealtimeOff);
  }
  final permitted = await ref
      .read(chatCallPermittedProvider.future)
      .timeout(const Duration(seconds: 3), onTimeout: () => null);
  if (permitted != true) return _blocked(RealtimeCallBlock.callNotPermitted);
  final api = ref.read(apiServiceProvider);
  final token = api?.authToken;
  if (api == null || token == null || TokenValidator.isApiKey(token)) {
    return _blocked(RealtimeCallBlock.noSessionToken);
  }
  final server = api.serverConfig;
  final chatId = active?.id;
  return (
    bridge: OpenWebUiRealtimeBridge(
      server: server,
      token: token,
      modelId: model.id,
      // A chat the server has not created yet is not named.
      chatId: chatId == null || chatId.contains(':') ? null : chatId,
      httpClient: ServerTlsHttpClientFactory.requiresCustomHttpClient(server)
          ? ServerTlsHttpClientFactory.createHttpClient(server)
          : null,
    ),
    block: null,
  );
}
