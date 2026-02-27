import 'package:drift/drift.dart';

/// ChangeSets table definition
/// Stores change-set records for sync operations
class ChangeSets extends Table {
  /// UUID string primary key
  TextColumn get id => text()();

  /// Name of the affected table (e.g., 'students', 'attendance', 'payments')
  TextColumn get table => text()();

  /// ID of the affected record
  TextColumn get recordId => text()();

  /// Operation type: 'INSERT', 'UPDATE', 'STATUS_CHANGE', or 'DELETE'
  TextColumn get operation => text()();

  /// JSON string representation of the changes
  TextColumn get payload => text()();

  /// Timestamp when the change occurred
  DateTimeColumn get timestamp => dateTime().withDefault(currentDateAndTime)();

  /// ID of the user who made the change
  TextColumn get userId => text()();

  /// Version number for conflict detection
  IntColumn get version => integer()();

  /// ID of the device that created this change-set (for sync).
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [];

  @override
  List<String> get customConstraints => [
        // Ensure operation is one of the valid values
        "CHECK(operation IN ('INSERT', 'UPDATE', 'STATUS_CHANGE', 'DELETE'))",
      ];
}
