import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// The web's folder actions: `POST /api/v1/folders/{id}/read`
/// (`routers/folders.py:mark_folder_chats_read_by_id`) and
/// `GET /api/v1/chats/folder/{id}` (`routers/chats.py:get_chats_by_folder_id`).
void main() {
  test('markFolderRead posts to the folder read route', () async {
    final adapter = _RecordingAdapter({
      'POST /api/v1/folders/f1/read': {
        'folder_id': 'f1',
        'folder_ids': ['f1', 'f2'],
        'updated_count': 3,
        'folder_unread_counts': {'f1': 0, 'f2': 0},
      },
    });
    final api = _buildApi(adapter);

    final body = await api.markFolderRead('f1');

    check(adapter.requests).deepEquals(['POST /api/v1/folders/f1/read']);
    check(body?['updated_count']).equals(3);
    final folderIds = (body!['folder_ids'] as List).cast<String>();
    check(folderIds).deepEquals(['f1', 'f2']);
  });

  test('markFolderRead answers null when the body is not a map', () async {
    final api = _buildApi(
      _RecordingAdapter({'POST /api/v1/folders/f1/read': <Object?>[]}),
    );

    check(await api.markFolderRead('f1')).isNull();
  });

  test('getFolderChats reads the folder chats route, id encoded', () async {
    final adapter = _RecordingAdapter({
      'GET /api/v1/chats/folder/f%201': [
        {'id': 'c1', 'title': 'One', 'chat': {'messages': []}},
        {'id': 'c2', 'title': 'Two'},
      ],
    });
    final api = _buildApi(adapter);

    final chats = await api.getFolderChats('f 1');

    check(adapter.requests).deepEquals(['GET /api/v1/chats/folder/f%201']);
    check(chats.map((c) => c['id'])).deepEquals(['c1', 'c2']);
  });

  test('getFolderChats answers an empty list for a non-list body', () async {
    final api = _buildApi(
      _RecordingAdapter({
        'GET /api/v1/chats/folder/f1': {'detail': 'Not found'},
      }),
    );

    check(await api.getFolderChats('f1')).isEmpty();
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.responses);

  /// `'<METHOD> <path>'` -> body. A missing route answers 404.
  final Map<String, Object?> responses;
  final List<String> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    // `options.path` keeps the percent-encoding as sent; `uri.path` decodes it.
    final key = '${options.method} ${options.path}';
    requests.add(key);
    final body = responses[key];
    if (body == null) {
      return ResponseBody.fromString('{}', 404, headers: _jsonHeaders);
    }
    return ResponseBody.fromString(jsonEncode(body), 200, headers: _jsonHeaders);
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