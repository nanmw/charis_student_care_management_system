import 'package:drift/drift.dart';

import 'academic_sessions.dart';

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

  /// Subject id (references subjects.id)
  IntColumn get subjectId => integer().nullable()();

  /// When the test was recorded
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When the test was last updated (null for tests that haven't been updated)
  DateTimeColumn get updatedAt => dateTime().nullable()();

  /// Academic session (e.g. "2024-2025"). Nullable for legacy records.
  TextColumn get academicSession => text().nullable()();

  /// Academic session foreign key (preferred over raw string for new data).
  IntColumn get academicSessionId =>
      integer().nullable().references(AcademicSessions, #id)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        'CHECK(score >= 0 AND score <= 100)',
      ];
}
