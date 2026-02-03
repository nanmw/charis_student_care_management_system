import 'package:drift/drift.dart';

/// Test scores table: one row per test per student.
/// Score 0-100; pass = score >= 70; outstanding = count where score < 70.
class Tests extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Student id (references students.id)
  IntColumn get studentId => integer()();

  /// Score 0-100
  IntColumn get score => integer()();

  /// Optional label (e.g. "Quiz 1")
  TextColumn get label => text().nullable()();

  /// When the test was recorded
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK(score >= 0 AND score <= 100)',
      ];
}
