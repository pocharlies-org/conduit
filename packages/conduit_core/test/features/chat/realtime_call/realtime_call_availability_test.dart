import 'dart:async';

import 'package:checks/checks.dart';
import 'package:conduit_core/features/chat/providers/chat_providers.dart';
import 'package:conduit_core/features/chat/realtime_call/bridge_call_host.dart';
import 'package:conduit_core/features/chat/realtime_call/chat_bridge_call_host.dart';
import 'package:conduit_core/features/chat/realtime_call/realtime_bridge_transport.dart';
import 'package:conduit_core/features/chat/realtime_call/realtime_call_availability.dart';
import 'package:conduit_core/models/backend_config.dart';
import 'package:conduit_core/models/chat_message.dart';
import 'package:conduit_core/models/conversation.dart';
import 'package:conduit_core/models/message_voice.dart';
import 'package:conduit_core/models/model.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/settings_service.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:conduit_core/voice/voice_session.dart';
import 'package:riverpod/riverpod.dart';
import 'package:test/test.dart';

final class _Config extends BackendConfigNotifier {
  _Config(this.config);

  final BackendConfig? config;

  @override
  Future<BackendConfig?> build() async => config;
}

final class _Active extends ActiveConversationNotifier {
  _Active(this.conversation);

  final Conversation? conversation;

  @override
  Conversation? build() => conversation;
}

final class _Answering extends Notifier<bool> {
  @override
  bool build() => true;

  void finish() => state = false;
}

final _answeringProvider = NotifierProvider<_Answering, bool>(_Answering.new);

const _owuiModel = Model(id: 'llama3', name: 'Llama 3');

Conversation _chat(String id) => Conversation(
  id: id,
  title: 'Chat',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  Future<RealtimeCallRoute> route(
    Model model, {
    VoiceCallMode mode = VoiceCallMode.auto,
    bool? realtimeOn = true,
    bool? permitted = true,
    String token = 'eyJhbGciOiJIUzI1NiJ9.e30.sig',
    Conversation? active,
    bool newChat = false,
    bool? temporaryEnforced,
  }) async {
    final api = ApiService(
      serverConfig: const ServerConfig(
        id: 'server',
        name: 'Home',
        url: 'https://owui.example',
      ),
      workerManager: WorkerManager(),
    )..updateAuthToken(token);
    final container = ProviderContainer(
      overrides: [
        appSettingsProvider.overrideWithValue(AppSettings(voiceCallMode: mode)),
        activeConversationProvider.overrideWith(() => _Active(active)),
        apiServiceProvider.overrideWithValue(api),
        backendConfigProvider.overrideWith(
          () => _Config(BackendConfig(enableRealtimeCall: realtimeOn)),
        ),
        chatCallPermittedProvider.overrideWith((ref) async => permitted),
        if (temporaryEnforced != null)
          temporaryChatEnforcedProvider.overrideWithValue(temporaryEnforced),
      ],
    );
    addTearDown(container.dispose);
    await container.read(backendConfigProvider.future);
    return container.read(realtimeCallRouteResolverProvider)(
      model,
      newChat: newChat,
    );
  }

  test('the user can always choose Standard calls', () async {
    check((await route(_owuiModel, mode: VoiceCallMode.standard)).block)
        .equals(RealtimeCallBlock.standardChosen);
  });

  group('Open WebUI', () {
    test('a server with realtime calls gets its own bridge', () async {
      final result = await route(
        _owuiModel,
        active: Conversation(
          id: 'chat-1',
          title: 'Chat',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );

      final bridge = result.bridge;
      check(bridge).isA<OpenWebUiRealtimeBridge>();
      bridge as OpenWebUiRealtimeBridge;
      check(bridge.modelId).equals('llama3');
      check(bridge.chatId).equals('chat-1');
    });

    test('a call that starts a new chat does not name the open one', () async {
      final result = await route(
        _owuiModel,
        active: _chat('chat-1'),
        newChat: true,
      );

      check((result.bridge! as OpenWebUiRealtimeBridge).chatId).isNull();
    });

    test('a new chat the server keeps temporary stays Standard', () async {
      final result = await route(
        _owuiModel,
        active: _chat('chat-1'),
        newChat: true,
        temporaryEnforced: true,
      );

      check(result.block).equals(RealtimeCallBlock.temporaryChat);
    });

    test('a chat the server does not have yet is not named', () async {
      final result = await route(
        _owuiModel,
        active: Conversation(
          id: 'local:abc',
          title: 'Chat',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      );

      // A `local:` chat is a temporary one here; nothing new is named either.
      check(result.block).equals(RealtimeCallBlock.temporaryChat);
    });

    test('a server without realtime calls keeps them Standard', () async {
      check((await route(_owuiModel, realtimeOn: null)).block)
          .equals(RealtimeCallBlock.serverRealtimeOff);
      check((await route(_owuiModel, realtimeOn: false)).block)
          .equals(RealtimeCallBlock.serverRealtimeOff);
    });

    test(
      'an account that may not call, or is unknown, stays Standard',
      () async {
        check((await route(_owuiModel, permitted: false)).block)
            .equals(RealtimeCallBlock.callNotPermitted);
        check((await route(_owuiModel, permitted: null)).block)
            .equals(RealtimeCallBlock.callNotPermitted);
      },
    );

    test('an API key cannot open a realtime call', () async {
      check((await route(_owuiModel, token: 'sk-1234567890')).block)
          .equals(RealtimeCallBlock.noSessionToken);
    });
  });

  test('a call writes nothing to a chat it did not start in', () async {
    final container = ProviderContainer(
      overrides: [
        activeConversationProvider.overrideWith(
          () => _Active(_chat('chat-1')),
        ),
      ],
    );
    addTearDown(container.dispose);
    final host = container.read(
      Provider((ref) => ChatBridgeCallHost(ref, onNotice: (_) {})),
    );
    check(host.chatId).equals('chat-1');

    container.read(activeConversationProvider.notifier).set(_chat('chat-2'));

    // Nor does its voice read the chat open now.
    container.read(chatMessagesProvider.notifier).addMessages([
      ChatMessage(
        id: 'u2',
        role: 'user',
        content: 'Something private',
        timestamp: DateTime.utc(2026),
      ),
    ]);
    check(realtimeChatSnapshot(container.read(chatMessagesProvider)))
        .isNotEmpty();
    check(host.chatSnapshot()).isEmpty();
    await check(
      host.recordExchange(
        const RealtimeVoiceExchange(
          userText: 'Thanks',
          userVoice: {},
          voiceModel: 'gpt-realtime',
          replyText: 'You are welcome.',
          replyVoice: {},
        ),
      ),
    ).throws<StateError>();
    await check(host.delegate('Plan my week', userVoice: const {}))
        .throws<StateError>();
  });

  test('small talk waits while the chat is answering, apart from requests',
      () async {
    final container = ProviderContainer(
      overrides: [
        activeConversationProvider.overrideWith(
          () => _Active(_chat('chat-1')),
        ),
        isChatStreamingProvider.overrideWith(
          (ref) => ref.watch(_answeringProvider),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notices = <ChatVoiceModeNotice>[];
    final host = container.read(
      Provider((ref) => ChatBridgeCallHost(ref, onNotice: notices.add)),
    );

    // A typed answer the call did not start is still running: what was said
    // is held, and the call's writes go on.
    await host.recordExchange(
      const RealtimeVoiceExchange(
        userText: 'Thanks',
        userVoice: {},
        voiceModel: 'gpt-realtime',
        replyText: 'You are welcome.',
        replyVoice: {},
      ),
    );
    await pumpEventQueue();
    check(notices).isEmpty();
    // A request meanwhile hears that the chat is busy.
    final request = await host.delegate('Plan my week', userVoice: const {});
    check(request.state).equals(DelegatedTurnState.deferred);

    container.read(_answeringProvider.notifier).finish();
    await pumpEventQueue();
    // The held words are saved now; this container cannot store them.
    check(notices).deepEquals([ChatVoiceModeNotice.transcriptNotSaved]);
  });

  test('a call without a chat does not adopt one the user opens', () {
    final container = ProviderContainer(
      overrides: [activeConversationProvider.overrideWith(() => _Active(null))],
    );
    addTearDown(container.dispose);
    final host = container.read(
      Provider((ref) => ChatBridgeCallHost(ref, onNotice: (_) {})),
    );

    final opened = _chat('chat-2').copyWith(
      messages: [
        ChatMessage(
          id: 'u1',
          role: 'user',
          content: 'Earlier',
          timestamp: DateTime.utc(2026),
        ),
      ],
    );
    check(host.chatId).isNull();
    check(host.createdChat(opened)).isFalse();
  });

  test('the voice reads the chat with each answer labeled', () {
    final snapshot = realtimeChatSnapshot([
      ChatMessage(
        id: 'u1',
        role: 'user',
        content: 'Plan my trip',
        timestamp: DateTime.utc(2026),
      ),
      ChatMessage(
        id: 'a1',
        role: 'assistant',
        content:
            '<details type="reasoning" done="true">\n<summary>Thought</summary>\n'
            '> hmm\n</details>\nDay 1: Oslo.',
        timestamp: DateTime.utc(2026),
        metadata: const {
          kMessageVoiceMetadataKey: {
            'model': 'gpt-realtime',
            'speech': [
              {'transcript': 'Let me plan that.'},
            ],
          },
        },
      ),
      ChatMessage(
        id: 'a2',
        role: 'assistant',
        content: '',
        timestamp: DateTime.utc(2026),
        isStreaming: true,
      ),
    ]);

    check(snapshot).deepEquals([
      {'role': 'user', 'content': 'Plan my trip'},
      {
        'role': 'assistant',
        'content':
            '[Chat model answer; message a1; completed]\nDay 1: Oslo.\n'
            '${kHistoricalVoiceTranscriptPrefix}Let me plan that.',
      },
      {
        'role': 'assistant',
        'content': '[Chat model answer; message a2; working]',
      },
    ]);
  });
}

