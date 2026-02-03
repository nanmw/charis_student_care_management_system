import 'package:drift/drift.dart';

/// Students table definition
/// Stores student information with alphabetical sorting support
class Students extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Student surname (indexed for efficient alphabetical sorting)
  TextColumn get surname => text()();

  /// Student first name
  TextColumn get firstName => text()();

  /// Student status: Active, Withdrawn, or Transferred
  /// Defaults to 'Active'
  TextColumn get status => text().withDefault(const Constant('Active'))();

  /// Year (e.g. Year 1, Year 2)
  TextColumn get year => text().nullable()();

  /// Mode (e.g. Full-time, Hybrid)
  TextColumn get mode => text().nullable()();

  /// Admission year (e.g. 2024)
  TextColumn get admissionYear => text().nullable()();

  /// Contact info: email or phone
  TextColumn get contactInfo => text().nullable()();

  /// Email address
  TextColumn get email => text().nullable()();

  /// Handbook checkbox status
  BoolColumn get handbook => boolean().withDefault(const Constant(false))();

  /// Media release checkbox status
  BoolColumn get mediaRelease => boolean().withDefault(const Constant(false))();

  /// Accident waiver checkbox status
  BoolColumn get accidentWaiver => boolean().withDefault(const Constant(false))();

  /// Timestamp when record was created
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Timestamp when record was last updated
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Version number for optimistic locking and conflict detection
  /// Starts at 1, increments on each update
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [];

  @override
  List<String> get customConstraints => [
        // Ensure status is one of the valid values
        "CHECK(status IN ('Active', 'Withdrawn', 'Transferred'))",
      ];
}
