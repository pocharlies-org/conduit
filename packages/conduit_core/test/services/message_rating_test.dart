import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/message_rating.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// A rating writes the thumb into the message's annotation and the evaluation
/// (`ResponseMessage.svelte` `feedbackHandler`); the comment the web's rate
/// dialog collects lives in that same annotation (`RateComment.svelte`).
void main() {
  test('a thumb files an evaluation and annotates the message', () async {
    final server = _RatingServer();
    final rating = MessageRating(_buildApi(server));

    await rating.rate(chatId: 'c1', messageId: 'm1', rating: 1);

    final saved = server.lastChatWrite()!;
    final annotation = server.annotationIn(saved);
    check(annotation['rating']).equals(1);
    check(annotation['reason']).isNull();
    check(annotation['comment']).isNull();
    check(annotation['details']).isNull();
    final message = server.messageIn(saved);
    check(message['feedbackId']).equals('fb1');
    check(server.requests.any((r) => r.path == '/api/v1/evaluations/feedback'))
        .isTrue();
  });

  test('the comment is stored, and a new verdict clears it', () async {
    final server = _RatingServer();
    final rating = MessageRating(_buildApi(server));

    await rating.rate(
      chatId: 'c1',
      messageId: 'm1',
      rating: -1,
      comment: '  wrong directions  ',
    );

    check(server.annotationIn(server.lastChatWrite()!)['comment'])
        .equals('wrong directions');

    await rating.rate(chatId: 'c1', messageId: 'm1', rating: 1);

    check(server.annotationIn(server.lastChatWrite()!)['comment']).isNull();
  });

  test('rating twice updates the same evaluation', () async {
    final server = _RatingServer();
    final rating = MessageRating(_buildApi(server));

    await rating.rate(chatId: 'c1', messageId: 'm1', rating: 1);
    await rating.rate(chatId: 'c1', messageId: 'm1', rating: -1);

    final updates = server.requests
        .where((r) => r.path == '/api/v1/evaluations/feedback/fb1')
        .length;
    check(updates).equals(1);
  });

  test('a rating other than a thumb is refused', () async {
    final rating = MessageRating(_buildApi(_RatingServer()));

    await check(
      rating.rate(chatId: 'c1', messageId: 'm1', rating: 0),
    ).throws<ArgumentError>();
  });
}

class _RatingServer implements HttpClientAdapter {
  final List<({String method, String path, Map<String, dynamic>? body})>
  requests = [];
  int _feedbackIds = 0;

  /// The chat's message, kept between calls so a second rating sees the
  /// `feedbackId` and the annotation the first one wrote.
  Map<String, dynamic> _message = {
    'id': 'm1',
    'model': 'test-model',
    'parentId': null,
  };

  Map<String, dynamic>? _lastChatWrite;

  Map<String, dynamic>? lastChatWrite() => _lastChatWrite;

  Map<String, dynamic> annotationIn(Map<String, dynamic> write) {
    final messages = _messagesIn(write);
    return Map<String, dynamic>.from(
      (messages['m1'] as Map)['annotation'] as Map,
    );
  }

  Map<String, dynamic> messageIn(Map<String, dynamic> write) =>
      Map<String, dynamic>.from(_messagesIn(write)['m1'] as Map);

  Map<String, dynamic> _messagesIn(Map<String, dynamic> write) {
    final chat = write['chat'] as Map;
    final history = chat['history'] as Map;
    return Map<String, dynamic>.from(history['messages'] as Map);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Map<String, dynamic>? body;
    if (requestStream != null) {
      final bytes = await requestStream.fold<List<int>>(<int>[], (
        all,
        chunk,
      ) => all..addAll(chunk));
      if (bytes.isNotEmpty) {
        body = Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
      }
    }
    requests.add((method: options.method, path: options.path, body: body));

    if (options.method == 'GET' && options.path == '/api/v1/chats/c1') {
      return _json({
        'chat': {
          'history': {
            'messages': {'m1': _clone(_message)},
          },
        },
      });
    }
    if (options.method == 'POST' &&
        options.path == '/api/v1/evaluations/feedback') {
      _feedbackIds++;
      return _json({'id': 'fb$_feedbackIds'});
    }
    if (options.method == 'POST' &&
        options.path.startsWith('/api/v1/evaluations/feedback/')) {
      return _json({'id': options.path.split('/').last});
    }
    if (options.method == 'POST' && options.path == '/api/v1/chats/c1') {
      _lastChatWrite = body;
      final messages = _messagesIn(body!);
      _message = Map<String, dynamic>.from(messages['m1'] as Map);
      return _json({'id': 'c1'});
    }
    return _json(<String, Object?>{});
  }

  static Map<String, dynamic> _clone(Map<String, dynamic> value) =>
      Map<String, dynamic>.from(jsonDecode(jsonEncode(value)) as Map);

  ResponseBody _json(Object? body) => ResponseBody.fromString(
    jsonEncode(body),
    200,
    headers: const {
      Headers.contentTypeHeader: ['application/json'],
    },
  );

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