import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:conduit_core/providers/app_providers.dart';

part 'sidebar_tag_providers.g.dart';

/// Every chat tag this account has (`GET /api/v1/chats/all/tags`), sorted, for
/// the sidebar's tag filter and the tag editor's suggestions.
///
/// The server drops a tag once no chat carries it, so this list is refreshed
/// after an add or a remove rather than patched in place.
@Riverpod(keepAlive: true)
Future<List<String>> chatTagNames(Ref ref) async {
  final api = ref.watch(apiServiceProvider);
  if (api == null) return const <String>[];
  final tags = await api.getAllChatTags();
  final names = <String>{
    for (final tag in tags)
      if (tag['name'] case final String name when name.isNotEmpty) name,
  }.toList()..sort();
  return names;
}

/// The tag the chat list is filtered by, or null for the whole list.
@Riverpod(keepAlive: true)
class ChatTagFilter extends _$ChatTagFilter {
  @override
  String? build() => null;

  void set(String? tag) => state = tag?.isEmpty ?? true ? null : tag;
}