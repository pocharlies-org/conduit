part of 'api_service.dart';

mixin _WorkspaceSearchApi on _ApiServiceBase {
  /// GET `/api/v1/search` (`routers/search.py:425`): chats, channel messages
  /// and notes in one ranked page, grouped by the `kind` of each hit.
  ///
  /// [kind] is `'all'` or one of `'chat'`, `'message'`, `'note'`; [sharing] is
  /// `'all'`, `'mine'` or `'shared'`. A non-empty [scope] (`folder:<id>` or
  /// `channel:<id>`) narrows the search to that folder or channel.
  Future<WorkspaceSearchResults> searchWorkspace({
    required String query,
    String kind = 'all',
    String sharing = 'all',
    String scope = '',
    int page = 1,
  }) async {
    _traceApi('Searching the workspace: $query ($kind/$sharing/$scope)');
    final response = await _dio.get(
      '/api/v1/search',
      queryParameters: {
        'q': query,
        'kind': kind,
        'sharing': sharing,
        'scope': scope,
        'page': page,
      },
    );
    return WorkspaceSearchResults.fromJson(response.data);
  }
}