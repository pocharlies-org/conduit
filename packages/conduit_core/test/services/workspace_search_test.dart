import 'dart:convert';
import 'dart:typed_data';

import 'package:checks/checks.dart';
import 'package:conduit_core/models/server_config.dart';
import 'package:conduit_core/models/workspace_search.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit_core/services/worker_manager.dart';
import 'package:dio/dio.dart';
import 'package:test/test.dart';

/// The body `GET /api/v1/search` answers (`routers/search.py`,
/// `SearchResponse`): one ranked page of chats, channel messages and notes.
const _searchBody = {
  'items': [
    {
      'id': 'c1',
      'kind': 'chat',
      'title': 'Budget talk',
      'context': 'Work',
      'snippet': 'the <mark>budget</mark> for Q4',
      'preview': 'longer passage',
      'url': '/c/c1?message=m2',
      'updated_at': 1700000000,
      'shared': false,
      'pinned': true,
      'rank': 1,
    },
    {
      'id': 'm7',
      'kind': 'message',
      'title': 'Message',
      'context': '#general',
      'snippet': 'the <mark>budget</mark> is late',
      'preview': 'the budget is late',
      'url': '/channels/ch9?thread=m7&message=m7',
      'updated_at': 1699999000,
      'shared': true,
      'pinned': false,
      'rank': 3,
    },
    {
      'id': 'n3',
      'kind': 'note',
      'title': 'Q4 budget',
      'context': 'Personal note',
      'snippet': 'quarterly <mark>budget</mark>',
      'preview': 'quarterly budget',
      'url': '/notes/n3?search=budget',
      'updated_at': 1699998000,
      'shared': false,
      'pinned': false,
      'rank': 2,
    },
    {
      'id': 's4',
      'kind': 'chat',
      'title': 'Shared plan',
      'context': 'Shared snapshot',
      'snippet': 'a <mark>budget</mark> already shared',
      'preview': 'a budget already shared',
      'url': '/s/s4',
      'updated_at': 1699997000,
      'shared': true,
      'pinned': false,
      'rank': 3,
    },
  ],
  'has_more': true,
  'kinds': ['chat', 'message', 'note'],
  'scopes': ['folder:f1', 'channel:ch9'],
};

void main() {
  test('searchWorkspace asks /api/v1/search with its filters', () async {
    final adapter = _RecordingAdapter(_searchBody);
    final api = _buildApi(adapter);

    final page = await api.searchWorkspace(
      query: 'budget',
      kind: 'note',
      sharing: 'mine',
      scope: 'folder:f1',
      page: 2,
    );

    check(adapter.requests).deepEquals(['GET /api/v1/search']);
    final query = adapter.query!;
    check(query['q']).equals('budget');
    check(query['kind']).equals('note');
    check(query['sharing']).equals('mine');
    check(query['scope']).equals('folder:f1');
    check(query['page']).equals(2);
    check(page.hits).isNotEmpty();
  });

  test('the answer becomes typed hits, kinds and scopes', () async {
    final api = _buildApi(_RecordingAdapter(_searchBody));

    final page = await api.searchWorkspace(query: 'budget');

    check(page.hits.length).equals(4);
    check(page.hasMore).isTrue();
    check(page.kinds).deepEquals(WorkspaceSearchKind.values);
    check(page.scopes).deepEquals(['folder:f1', 'channel:ch9']);

    final chat = page.hits.first;
    check(chat.kind).equals(WorkspaceSearchKind.chat);
    check(chat.title).equals('Budget talk');
    check(chat.context).equals('Work');
    check(chat.snippet).equals('the <mark>budget</mark> for Q4');
    check(chat.pinned).isTrue();
    check(chat.updatedAt).equals(
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
    );
    check(chat.isSnapshot).isFalse();
  });

  test('a page groups its hits by kind, in the server order', () async {
    final api = _buildApi(_RecordingAdapter(_searchBody));

    final page = await api.searchWorkspace(query: 'budget');

    check(page.of(WorkspaceSearchKind.chat).map((hit) => hit.id))
        .deepEquals(['c1', 's4']);
    check(page.of(WorkspaceSearchKind.message).single.id).equals('m7');
    check(page.of(WorkspaceSearchKind.note).single.id).equals('n3');
  });

  test('a message hit names its channel and a snapshot is read-only', () async {
    final api = _buildApi(_RecordingAdapter(_searchBody));

    final page = await api.searchWorkspace(query: 'budget');

    check(page.of(WorkspaceSearchKind.message).single.channelId).equals('ch9');
    check(page.of(WorkspaceSearchKind.note).single.channelId).isNull();
    check(
      page.hits.where((hit) => hit.isSnapshot).map((hit) => hit.id),
    ).deepEquals(['s4']);
  });

  test('an empty answer is a page without hits, not an error', () async {
    final api = _buildApi(
      _RecordingAdapter(const {
        'items': <Object?>[],
        'has_more': false,
        'kinds': ['chat'],
        'scopes': <Object?>[],
      }),
    );

    final page = await api.searchWorkspace(query: 'nothing');

    check(page.hits).isEmpty();
    check(page.hasMore).isFalse();
    check(page.kinds).deepEquals([WorkspaceSearchKind.chat]);
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.body);

  final Object? body;
  final List<String> requests = [];
  Map<String, dynamic>? query;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.method} ${options.path}');
    query = options.queryParameters;
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: const {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

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