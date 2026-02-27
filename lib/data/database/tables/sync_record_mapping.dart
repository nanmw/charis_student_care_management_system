import 'package:drift/drift.dart';

/// Maps remote (other device) record_id to local primary key for sync.
/// Populated when we apply an INSERT from another device so later UPDATEs can find the row.
class SyncRecordMapping extends Table {
  /// Affected table (e.g. 'students', 'payments'). Named entityTable to avoid clashing with Table.tableName.
  TextColumn get entityTable => text().named('table_name')();

  /// Record id from the change-set (sender's id as string)
  TextColumn get recordId => text()();

  /// Our local primary key for that record
  IntColumn get localId => integer()();

  @override
  Set<Column> get primaryKey => {entityTable, recordId};
}
