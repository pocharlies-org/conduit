import 'package:conduit_core/models/conversation.dart';
import 'package:conduit/features/navigation/widgets/sidebar_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sidebar_page_test_support.dart';

/// The sidebar's tag filter (`getAllTags` + the per-tag narrowing in
/// `Sidebar.svelte`): tapping a tag narrows the list, tapping it again brings
/// the whole list back.
void main() {
  testWidgets('a tag chip narrows the chat list and its release restores it', (
    tester,
  ) async {
    final timestamp = DateTime(2026, 1, 1);
    final work = Conversation(
      id: 'work-chat',
      title: 'Work Chat',
      createdAt: timestamp,
      updatedAt: timestamp,
      lastReadAt: timestamp,
      tags: const ['work'],
      messages: const [],
    );
    final home = Conversation(
      id: 'home-chat',
      title: 'Home Chat',
      createdAt: timestamp,
      updatedAt: timestamp,
      lastReadAt: timestamp,
      tags: const ['home'],
      messages: const [],
    );

    await tester.pumpWidget(
      sidebarTestBuildHarness(
        controllers: SidebarTestSidebarHarnessControllers(),
        conversations: [work, home],
        chatTags: const [
          {'id': 'home', 'name': 'home'},
          {'id': 'work', 'name': 'work'},
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SidebarPage), findsOneWidget);
    expect(find.text('Work Chat'), findsOneWidget);
    expect(find.text('Home Chat'), findsOneWidget);

    final workChip = find.widgetWithText(FilterChip, 'work');
    expect(workChip, findsOneWidget);

    await tester.tap(workChip);
    await tester.pumpAndSettle();
    expect(find.text('Work Chat'), findsOneWidget);
    expect(find.text('Home Chat'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'work'));
    await tester.pumpAndSettle();
    expect(find.text('Work Chat'), findsOneWidget);
    expect(find.text('Home Chat'), findsOneWidget);
  });
}