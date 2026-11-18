import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// The chat tag routes the app uses: `GET /api/v1/chats/all/tags`,
/// `POST`/`DELETE /api/v1/chats/{id}/tags` and `POST /api/v1/chats/tags`
/// (`routers/chats.py`, the calls `Tags.svelte` makes).
void main() {
  test('getAllChatTags reads the account-wide tag list', () async {
    final adapter = _RecordingAdapter({
      'GET /api/v1/chats/all/tags': [
        {'id': 'work', 'name': 'work'},
        {'id': 'home', 'name': 'home'},
      ],
    });
    final api = _buildApi(adapter);

    final tags = await api.getAllChatTags();

    check(adapter.requests).deepEquals(['GET /api/v1/chats/all/tags']);
    check(tags.map((t) => t['name'])).deepEquals(['work', 'home']);
  });

  test('addChatTag posts the name and answers the chat tags', () async {
    final adapter = _RecordingAdapter({
      'POST /api/v1/chats/c1/tags': [
        {'id': 'work', 'name': 'work'},
      ],
    });
    final api = _buildApi(adapter);

    final tags = await api.addChatTag('c1', 'work');

    check(adapter.requests).deepEquals(['POST /api/v1/chats/c1/tags']);
    check(adapter.bodies.single as Map<String, dynamic>).deepEquals({
      'name': 'work',
    });
    check(tags.map((t) => t['name'])).deepEquals(['work']);
  });

  test('removeChatTag deletes with the name in the body', () async {
    final adapter = _RecordingAdapter({
      'DELETE /api/v1/chats/c1/tags': <Object?>[],
    });
    final api = _buildApi(adapter);

    final tags = await api.removeChatTag('c1', 'work');

    check(adapter.requests).deepEquals(['DELETE /api/v1/chats/c1/tags']);
    check(adapter.bodies.single as Map<String, dynamic>).deepEquals({
      'name': 'work',
    });
    check(tags).isEmpty();
  });

  test('getChatsByTag sends the tag and the page window', () async {
    final adapter = _RecordingAdapter({
      'POST /api/v1/chats/tags': [
        {'id': 'c1', 'title': 'One'},
      ],
    });
    final api = _buildApi(adapter);

    final chats = await api.getChatsByTag('work', limit: 20);

    check(adapter.bodies.single as Map<String, dynamic>).deepEquals({
      'name': 'work',
      'skip': 0,
      'limit': 20,
    });
    check(chats.single['id']).equals('c1');
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.responses);

  /// `'<METHOD> <path>'` -> body. A missing route answers 404.
  final Map<String, Object?> responses;
  final List<String> requests = [];
  final List<Object?> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    requests.add(key);
    bodies.add(options.data);
    final body = responses[key];
    if (body == null) {
      return ResponseBody.fromString('{}', 404, headers: _jsonHeaders);
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: _jsonHeaders,
    );
  }

  static const _jsonHeaders = {
    Headers.contentTypeHeader: ['application/json'],
  };

  @override
  void close({bool force = false}) {}
}

ApiService _buildApi(HttpClientAdapter adapter) {
  final service = ApiService(
    serverConfig: const ServerConfig(
      id: 'test',
      name: 'Test',
      url: 'http://localhost:0',
    ),
    workerManager: WorkerManager(),
  );
  service.dio.httpClientAdapter = adapter;
  service.dio.interceptors.clear();
  return service;
}