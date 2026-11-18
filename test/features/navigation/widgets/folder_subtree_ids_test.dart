import 'package:checks/checks.dart';
import 'package:conduit/features/navigation/widgets/chats_drawer.dart';
import 'package:conduit_core/models/folder.dart';
import 'package:flutter_test/flutter_test.dart';

/// The web counts a folder's chats as its own plus those of every subfolder
/// (`routers/chats.py:get_chats_by_folder_id`); read-marking and delete use
/// the same subtree, so the walk has to close over nested folders.
void main() {
  test('collects nested descendants and nothing else', () {
    const folders = [
      Folder(id: 'a', name: 'A'),
      Folder(id: 'b', name: 'B', parentId: 'a'),
      Folder(id: 'c', name: 'C', parentId: 'b'),
      Folder(id: 'd', name: 'D'),
    ];

    check(folderSubtreeIds(folders, 'a')).deepEquals({'a', 'b', 'c'});
  });

  test('a leaf folder is its own subtree', () {
    const folders = [
      Folder(id: 'a', name: 'A'),
      Folder(id: 'b', name: 'B', parentId: 'a'),
    ];

    check(folderSubtreeIds(folders, 'b')).deepEquals({'b'});
  });

  test('terminates on a parent cycle', () {
    const folders = [
      Folder(id: 'a', name: 'A', parentId: 'b'),
      Folder(id: 'b', name: 'B', parentId: 'a'),
    ];

    check(folderSubtreeIds(folders, 'a')).deepEquals({'a', 'b'});
  });
}
