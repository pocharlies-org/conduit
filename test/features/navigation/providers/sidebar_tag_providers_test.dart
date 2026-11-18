import 'package:checks/checks.dart';
import 'package:conduit_core/providers/app_providers.dart';
import 'package:conduit_core/services/api_service.dart';
import 'package:conduit/features/navigation/providers/sidebar_tag_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

/// The sidebar's tag filter: the account's tags (`getAllTags` in
/// `Sidebar.svelte`) name-deduplicated and sorted, and the one tag the list is
/// narrowed to.
void main() {
  test('chatTagNames sorts the names and drops repeats and blanks', () async {
    final api = _TagsApi([
      {'id': 'work', 'name': 'work'},
      {'id': 'home', 'name': 'home'},
      {'id': 'work-dup', 'name': 'work'},
      {'id': '', 'name': ''},
      {'id': 'travel'},
    ]);
    final container = _container(api);
    addTearDown(container.dispose);

    final names = await container.read(chatTagNamesProvider.future);

    check(names).deepEquals(['home', 'work']);
  });

  test('chatTagNames answers empty with no server', () async {
    final container = _container(null);
    addTearDown(container.dispose);

    check(await container.read(chatTagNamesProvider.future)).isEmpty();
  });

  test('ChatTagFilter narrows to one tag and clears back to all', () {
    final container = _container(null);
    addTearDown(container.dispose);

    check(container.read(chatTagFilterProvider)).isNull();

    container.read(chatTagFilterProvider.notifier).set('work');
    check(container.read(chatTagFilterProvider)).equals('work');

    container.read(chatTagFilterProvider.notifier).set('');
    check(container.read(chatTagFilterProvider)).isNull();

    container.read(chatTagFilterProvider.notifier).set('home');
    container.read(chatTagFilterProvider.notifier).set(null);
    check(container.read(chatTagFilterProvider)).isNull();
  });
}

ProviderContainer _container(ApiService? api) => ProviderContainer(
  overrides: [apiServiceProvider.overrideWithValue(api)],
);

final class _TagsApi extends Mock implements ApiService {
  _TagsApi(this.tags);

  final List<Map<String, dynamic>> tags;

  @override
  Future<List<Map<String, dynamic>>> getAllChatTags() async => tags;
}