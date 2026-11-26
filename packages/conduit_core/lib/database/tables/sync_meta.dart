import 'package:drift/drift.dart';

/// Key-value sync bookkeeping (CDT-RFC-001 §6).
///
/// Keys: `pull_watermark`, `archived_pull_watermark` (OWU-163: the archived-chat
/// axis, same seconds clock as `pull_watermark`, never frozen by it),
/// `last_full_reconcile_at`, `schema_fixture_hash`;
/// Phase 5 adds `notes_pull_watermark` (nanoseconds — never compared with
/// chat watermarks, see D-11).
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
