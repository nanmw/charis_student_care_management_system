import 'package:drift/drift.dart';

/// Daily attendance table: one row per student per date.
/// Stores present (0/1) and notes.
class Attendance extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Date of attendance (stored at midnight UTC)
  DateTimeColumn get date => dateTime()();

  /// Student id (references students.id)
  IntColumn get studentId => integer()();

  /// Present (0 = no, 1 = yes)
  IntColumn get present => integer().withDefault(const Constant(0))();

  /// Optional notes
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {date, studentId},
      ];

  @override
  List<String> get customConstraints => [
        'CHECK(present IN (0, 1))',
      ];
}
