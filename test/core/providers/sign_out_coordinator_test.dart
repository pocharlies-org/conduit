import 'dart:io';

import 'package:checks/checks.dart';
import 'package:conduit_core/database/app_database.dart';
import 'package:conduit_core/database/database_provider.dart';
import 'package:conduit_core/database/database_manager.dart';
import 'package:conduit_core/database/mappers/chat_blob_mapper.dart';
import 'package:conduit_core/persistence/persistence_keys.dart';
import 'package:conduit_core/persistence/preferences_store.dart';
import 'package:conduit_core/ports/database_opener.dart';
import 'package:conduit_core/providers/host_ports.dart';
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Wipes the device stores the way the real full-data clear does.
/// Storage whose account registry, and everything else, cannot be read.
/// Opens databases in [directory] the way drift_flutter names them.
final class _DirectoryDatabaseOpener implements DatabaseOpenerPort {
  const _DirectoryDatabaseOpener(this.directory);

  final Directory directory;

  @override
  QueryExecutor open(String fileName) =>
      NativeDatabase(File(p.join(directory.path, '$fileName.sqlite')));

  @override
  Future<Directory> databaseDirectory() async => directory;
}

Directory _tempDatabaseDirectory() {
  final directory = Directory.systemTemp.createTempSync('conduit_sign_out_db');
  addTearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });
  return directory;
}

/// Writes a database file for [accountId] where the account manager looks.
File _accountDatabaseFile(Directory directory, String accountId) => File(
  p.join(directory.path, '${DatabaseManager.fileNameFor(accountId)}.sqlite'),
)..writeAsStringSync('chats of $accountId');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    PreferencesStore.debugReset();
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await PreferencesStore.ensureInitialized();
  });

  tearDown(PreferencesStore.debugReset);

  // Riverpod keeps a notifier instance across `invalidate`, so a completed
  // clear must release the controllers' sign-out barriers itself. Otherwise
  // their rebuilds keep serving the connections captured before the wipe.
  test('the next start deletes them before any database opens', () async {
    final directory = _tempDatabaseDirectory();
    final leftover = _accountDatabaseFile(directory, 'signed-out');
    // Signed in to after the sign-out that could not finish.
    final later = _accountDatabaseFile(directory, 'signed-in-later');
    final directLocal = File(
      p.join(directory.path, '$kDirectLocalDatabaseFileName.sqlite'),
    )..writeAsStringSync('device chats');
    await PreferencesStore.put(
      PreferenceKeys.pendingAccountDatabaseWipe,
      pendingAccountDatabaseWipeValue({
        DatabaseManager.fileNameFor('signed-out'),
      }),
    );
    final container = ProviderContainer(
      overrides: [
        databaseOpenerProvider.overrideWithValue(
          _DirectoryDatabaseOpener(directory),
        ),
      ],
    );
    addTearDown(container.dispose);

    final manager = container.read(databaseManagerProvider);
    final attempt = manager.openForServerIdIfReady('signed-out');
    check(attempt).isA<DatabaseOpenDeferred>();
    await (attempt as DatabaseOpenDeferred).retryAfter;
    for (var i = 0; i < 20; i++) {
      if (!PreferencesStore.containsKey(
        PreferenceKeys.pendingAccountDatabaseWipe,
      )) {
        break;
      }
      await Future<void>.delayed(Duration.zero);
    }

    check(leftover.existsSync()).isFalse();
    check(later.existsSync()).isTrue();
    check(directLocal.existsSync()).isTrue();
    check(
      PreferencesStore.containsKey(PreferenceKeys.pendingAccountDatabaseWipe),
    ).isFalse();
  });

  test('direct-local purge reopens an empty on-device chat store', () async {
    final tempDir = Directory.systemTemp.createTempSync(
      'conduit_sign_out_direct_local',
    );
    final manager = DatabaseManager(
      databaseDirectory: () async => tempDir,
      openDatabase: (fileName) => AppDatabase(
        NativeDatabase(File(p.join(tempDir.path, '$fileName.sqlite'))),
      ),
    );
    addTearDown(() async {
      await manager.closeActive();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });
    final container = ProviderContainer(
      overrides: [
        directLocalDatabaseManagerProvider.overrideWithValue(manager),
      ],
    );
    addTearDown(container.dispose);

    final database = manager.openForServerId(kDirectLocalDatabaseId);
    await database.chatsDao.upsertLocalOnlyChat(
      rows: ChatBlobMapper.blobToRows(
        chatId: 'device-chat',
        blob: const <String, dynamic>{
          'title': 'Device chat',
          'history': <String, dynamic>{
            'messages': <String, dynamic>{},
            'currentId': null,
          },
        },
        title: 'Device chat',
        folderId: null,
        pinned: false,
        archived: false,
        createdAt: 1,
        updatedAt: 1,
      ),
    );
    check(await database.chatsDao.getChat('device-chat')).isNotNull();

    await container.read(directLocalDatabasePurgeProvider)();
    final reopened = manager.openForServerId(kDirectLocalDatabaseId);

    check(await reopened.chatsDao.getChat('device-chat')).isNull();
  });
}
