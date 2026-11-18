import 'package:conduit/features/navigation/widgets/chats_drawer.dart';
import 'package:conduit_core/models/conversation.dart';
import 'package:conduit_core/models/folder.dart';
import 'package:conduit/shared/utils/conversation_context_menu.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sidebar_page_test_support.dart';

/// The web's folder menu offers mark-read, export-to-JSON and delete, and its
/// delete warns with the chats the folder really holds — the folder's own plus
/// its subfolders' (`routers/chats.py:get_chats_by_folder_id`).
void main() {
  testWidgets('folder menu offers the web actions and counts subtree chats', (
    tester,
  ) async {
    final controllers = SidebarTestSidebarHarnessControllers();
    final timestamp = DateTime(2026, 1, 1);
    Conversation chat(String id, String folderId) => Conversation(
      id: id,
      title: id,
      createdAt: timestamp,
      updatedAt: timestamp,
      lastReadAt: timestamp,
      folderId: folderId,
      messages: const [],
    );

    await tester.pumpWidget(
      sidebarTestBuildHarness(
        controllers: controllers,
        folders: const [
          Folder(id: 'parent-folder', name: 'Parent Folder', isExpanded: true),
          Folder(
            id: 'child-folder',
            name: 'Child Folder',
            parentId: 'parent-folder',
            isExpanded: true,
          ),
        ],
        conversations: [
          chat('own-chat', 'parent-folder'),
          chat('nested-chat', 'child-folder'),
        ],
      ),
    );
    await tester.pumpAndSettle();

    final menu = tester.widget<ConduitContextMenu>(
      find.ancestor(
        of: find.byKey(const ValueKey<String>('folder-open-parent-folder')),
        matching: find.byType(ConduitContextMenu),
      ),
    );
    final labels = menu.actions.map((action) => action.label).toList();
    expect(labels, contains('Mark as read'));
    expect(labels, contains('Export to JSON'));

    final delete = menu.actions.singleWhere((action) => action.label == 'Delete');
    await delete.onSelected();
    await tester.pumpAndSettle();

    expect(find.text('Delete Folder'), findsOneWidget);
    expect(
      find.text('This folder and its 2 chats will be deleted.'),
      findsOneWidget,
    );
  });
}