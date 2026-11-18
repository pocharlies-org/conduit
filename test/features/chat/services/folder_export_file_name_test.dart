import 'package:checks/checks.dart';
import 'package:conduit/features/chat/services/chat_backup_files.dart';
import 'package:flutter_test/flutter_test.dart';

/// `folder-<name>-export-<stamp>.json`, as the web's folder menu names the
/// file it downloads (`RecursiveFolder.svelte` `exportHandler`).
void main() {
  test('names the file after the folder and the moment', () {
    final name = folderExportFileName(
      'Trabajo',
      DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );

    check(name).equals('folder-Trabajo-export-1700000000000.json');
  });

  test('an unnamed folder is a folder', () {
    final name = folderExportFileName('   ', DateTime(2026));

    check(name).equals(
      'folder-folder-export-${DateTime(2026).millisecondsSinceEpoch}.json',
    );
  });
}
