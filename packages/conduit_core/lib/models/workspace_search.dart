/// One row of `GET /api/v1/search` (`routers/search.py` `SearchResult`):
/// a chat, a channel message or a note, already ranked by the server.
class WorkspaceSearchHit {
  const WorkspaceSearchHit({
    required this.id,
    required this.kind,
    required this.title,
    required this.context,
    required this.snippet,
    required this.url,
    this.updatedAt,
    this.shared = false,
    this.pinned = false,
  });

  /// `chat` is also what the server sends for a shared-chat snapshot.
  final WorkspaceSearchKind kind;
  final String id;
  final String title;

  /// Where the hit lives: the folder, the channel name or «Personal note».
  final String context;

  /// The highlighted excerpt the web paints under the title.
  final String snippet;

  /// The web's own route for the hit (`/c/…`, `/notes/…`, `/channels/…`,
  /// `/s/…`), kept so the app can read the ids the server intended.
  final String url;
  final DateTime? updatedAt;
  final bool shared;
  final bool pinned;

  /// Whether this is a read-only shared snapshot (`/s/<id>`), which the chat
  /// list cannot open as a live conversation.
  bool get isSnapshot => url.startsWith('/s/');

  /// The channel a `message` hit belongs to, read from `/channels/<id>?…`.
  String? get channelId {
    final path = Uri.tryParse(url)?.pathSegments ?? const <String>[];
    if (path.length < 2 || path.first != 'channels') return null;
    return path[1];
  }

  factory WorkspaceSearchHit.fromJson(Map<String, dynamic> json) {
    final updated = json['updated_at'];
    return WorkspaceSearchHit(
      id: json['id'] as String? ?? '',
      kind:
          WorkspaceSearchKind.fromWire(json['kind'] as String?) ??
          WorkspaceSearchKind.chat,
      title: json['title'] as String? ?? '',
      context: json['context'] as String? ?? '',
      snippet: json['snippet'] as String? ?? '',
      url: json['url'] as String? ?? '',
      updatedAt: updated is num
          ? DateTime.fromMillisecondsSinceEpoch(updated.toInt() * 1000)
          : updated is String
          ? DateTime.tryParse(updated)
          : null,
      shared: json['shared'] == true,
      pinned: json['pinned'] == true,
    );
  }
}

enum WorkspaceSearchKind {
  chat,
  message,
  note;

  /// What the `kind` query parameter takes: `'chat'`, `'message'` or `'note'`.
  String get wire => name;

  static WorkspaceSearchKind? fromWire(String? value) => switch (value) {
    'chat' => chat,
    'message' => message,
    'note' => note,
    _ => null,
  };
}

/// One page of `GET /api/v1/search`: the hits, whether another page exists,
/// the kinds the server searched and the scopes it offered.
class WorkspaceSearchResults {
  const WorkspaceSearchResults({
    this.hits = const [],
    this.hasMore = false,
    this.kinds = const [],
    this.scopes = const [],
  });

  final List<WorkspaceSearchHit> hits;
  final bool hasMore;

  /// The result kinds this account's server searched (`chat` always, plus
  /// `message`/`note` when channels or notes are enabled).
  final List<WorkspaceSearchKind> kinds;

  /// Folder and channel scopes the server offered, shaped `folder:<id>` and
  /// `channel:<id>`.
  final List<String> scopes;

  static WorkspaceSearchResults fromJson(Object? data) {
    if (data is! Map) return const WorkspaceSearchResults();
    final items = data['items'];
    return WorkspaceSearchResults(
      hits: [
        if (items is List)
          for (final item in items)
            if (item is Map)
              WorkspaceSearchHit.fromJson(Map<String, dynamic>.from(item)),
      ],
      hasMore: data['has_more'] == true,
      kinds: [
        for (final kind in (data['kinds'] as List? ?? const []))
          ?WorkspaceSearchKind.fromWire(kind as String?),
      ],
      scopes: [
        for (final scope in (data['scopes'] as List? ?? const []))
          if (scope is String) scope,
      ],
    );
  }

  /// The hits of [kind], in the server's order.
  List<WorkspaceSearchHit> of(WorkspaceSearchKind kind) =>
      hits.where((hit) => hit.kind == kind).toList(growable: false);
}