import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:checks/checks.dart';
import 'package:conduit_core/features/chat/realtime_call/bridge_commands.dart';
import 'package:conduit_core/features/chat/realtime_call/realtime_bridge_transport.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:test/test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final class _Socket implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  final sent = <Map<String, Object?>>[];
  Uri? uri;
  Map<String, String>? headers;
  var closed = false;

  WebSocketChannel connect(
    Uri uri,
    Map<String, String> headers, {
    HttpClient? httpClient,
  }) {
    this.uri = uri;
    this.headers = headers;
    return this;
  }

  void receive(Map<String, Object?> frame) => incoming.add(jsonEncode(frame));

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  late final WebSocketSink sink = _Sink(this);

  @override
  Future<void> get ready => Future.value();

  @override
  String? get protocol => null;

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Sink implements WebSocketSink {
  _Sink(this._socket);

  final _Socket _socket;

  @override
  void add(Object? data) =>
      _socket.sent.add(jsonDecode(data! as String) as Map<String, Object?>);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _socket.closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('Open WebUI bridge', () {
    OpenWebUiRealtimeBridge bridge(_Socket socket, {String? chatId}) =>
        OpenWebUiRealtimeBridge(
          server: const ServerConfig(
            id: 'server',
            name: 'Home',
            url: 'https://owui.example/sub/',
            customHeaders: {'CF-Access-Client-Id': 'id', 'Host': 'evil'},
          ),
          token: 'jwt',
          modelId: 'llama3',
          chatId: chatId,
          connect: socket.connect,
        );

    test('signs in with the session token in its first frame', () async {
      final socket = _Socket();
      final ready = bridge(socket).open();
      await _settle();

      check(socket.uri.toString())
          .equals('wss://owui.example/sub/api/v1/audio/realtime');
      check(socket.headers!).containsKey('CF-Access-Client-Id');
      check(socket.headers!.containsKey('Host')).isFalse();
      // A chat the server does not have yet is not named.
      check(socket.sent.single)
          .deepEquals({'type': 'auth', 'token': 'jwt', 'model_id': 'llama3'});

      socket.receive({
        'type': 'bridge.ready',
        'model': 'gpt-realtime',
        'voice': 'marin',
        'sample_rate': 24000,
      });
      check(await ready).equals((model: 'gpt-realtime', voice: 'marin'));
    });

    test('a bridge closed before it opens connects nothing', () async {
      final socket = _Socket();
      final transport = bridge(socket);
      await transport.close();

      await check(transport.open()).throws<RealtimeBridgeException>();
      check(socket.uri).isNull();
    });

    test('names a saved chat, and passes events through', () async {
      final socket = _Socket();
      final transport = bridge(socket, chatId: 'chat-1');
      final ready = transport.open();
      await _settle();
      check(socket.sent.single['chat_id']).equals('chat-1');
      socket.receive({
        'type': 'bridge.ready',
        'model': 'm',
        'voice': 'v',
        'sample_rate': 24000,
      });
      await ready;

      final events = <Map<String, Object?>>[];
      transport.events.listen(events.add);
      socket.receive({'type': 'bridge.pong'});
      socket.receive({'type': 'input_audio_buffer.speech_started'});
      transport.send(BridgeCommands.ping);
      await _settle();

      check(events.map((event) => event['type']))
          .deepEquals(['bridge.pong', 'input_audio_buffer.speech_started']);
      check(socket.sent.last).deepEquals(BridgeCommands.ping);
    });

    test("the server's refusal ends the call with its message", () async {
      final socket = _Socket();
      final transport = bridge(socket);
      final ready = transport.open();
      await _settle();
      socket.receive({
        'type': 'bridge.error',
        'message': 'Call permission denied',
      });

      await check(ready).throws<RealtimeBridgeException>();
      check(await transport.closed).equals('Call permission denied');
      check(socket.closed).isTrue();
    });

    test('audio at another rate is refused', () async {
      final socket = _Socket();
      final ready = bridge(socket).open();
      await _settle();
      socket.receive({
        'type': 'bridge.ready',
        'model': 'm',
        'voice': 'v',
        'sample_rate': 16000,
      });

      await check(ready).throws<RealtimeBridgeException>();
    });
  });

}
