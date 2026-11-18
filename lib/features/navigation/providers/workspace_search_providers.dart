import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:conduit_core/models/workspace_search.dart';
import 'package:conduit_core/providers/app_providers.dart';

part 'workspace_search_providers.g.dart';

/// What the global search field holds.
@Riverpod(keepAlive: true)
class WorkspaceSearchQuery extends _$WorkspaceSearchQuery {
  @override
  String build() => '';

  void set(String query) => state = query;
}

/// The kind the results are narrowed to, or null for every kind.
@Riverpod(keepAlive: true)
class WorkspaceSearchFilter extends _$WorkspaceSearchFilter {
  @override
  WorkspaceSearchKind? build() => null;

  void set(WorkspaceSearchKind? kind) => state = kind;
}

/// One page of `GET /api/v1/search` for the current query and filter, or null
/// while the field is empty (nothing has been asked yet).
@Riverpod(keepAlive: true)
Future<WorkspaceSearchResults?> workspaceSearchResults(Ref ref) async {
  final query = ref.watch(workspaceSearchQueryProvider).trim();
  if (query.isEmpty) return null;
  final api = ref.watch(apiServiceProvider);
  if (api == null) throw const WorkspaceSearchUnavailable();
  return api.searchWorkspace(
    query: query,
    kind: ref.watch(workspaceSearchFilterProvider)?.wire ?? 'all',
  );
}

/// The search could not run: there is no server to ask.
class WorkspaceSearchUnavailable implements Exception {
  const WorkspaceSearchUnavailable();

  @override
  String toString() => 'WorkspaceSearchUnavailable';
}