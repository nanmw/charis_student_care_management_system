import 'package:drift/drift.dart';

/// Unresolved sync conflicts (critical table changes that clash with local data).
/// Admin Level 01 resolves via modal: keep local or use incoming.
class SyncConflicts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Change-set id that we did not auto-apply
  TextColumn get changeSetId => text()();

  /// Affected table. Named entityTable to avoid clashing with Table.tableName.
  TextColumn get entityTable => text().named('table_name')();

  TextColumn get recordId => text()();

  /// Incoming payload (JSON string)
  TextColumn get incomingPayload => text()();

  /// Local snapshot when conflict was detected (JSON string)
  TextColumn get localSnapshot => text()();

  DateTimeColumn get detectedAt => dateTime()();

  /// Device that sent the conflicting change-set
  TextColumn get sourceDeviceId => text()();
}
