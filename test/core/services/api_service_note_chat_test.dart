import 'dart:convert';
import 'dart:typed_data';

import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('note chat', () {
    test('POSTs to the note chat route and returns the chat object', () async {
      final adapter = _FixedAdapter(<String, dynamic>{
        'id': 'chat-1',
        'title': 'Note chat',
        'chat': <String, dynamic>{'title': 'Note chat', 'models': <String>[]},
      });
      final api = _buildApi(adapter);

      final chat = await api.createNoteChat('note-1');

      expect(adapter.request?.method, 'POST');
      expect(adapter.request?.path, '/api/v1/notes/note-1/chat');
      expect(chat['id'], 'chat-1');
    });

    test('a non-object body is a FormatException, not a cast error', () async {
      final api = _buildApi(_FixedAdapter(const <Object>[]));

      await expectLater(api.createNoteChat('note-1'), throwsFormatException);
    });
  });
}

ApiService _buildApi(HttpClientAdapter adapter) {
  final api = ApiService(
    serverConfig: const ServerConfig(
      id: 'note-chat-test',
      name: 'Note chat test',
      url: 'https://example.test',
    ),
    workerManager: WorkerManager(),
    authToken: 'test-token',
  );
  api.dio.httpClientAdapter = adapter;
  return api;
}

final class _FixedAdapter implements HttpClientAdapter {
  _FixedAdapter(this.body);

  final Object body;
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
