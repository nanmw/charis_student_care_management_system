import 'package:drift/drift.dart';

import 'classes.dart';
import 'academic_sessions.dart';

/// Ministry hours entries: one row per ministry activity per student.
/// Approved = supervisor-approved; Pending = awaiting approval.
class MinistryEntries extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Student id (references students.id)
  IntColumn get studentId => integer()();

  /// Year (e.g. "2023", "2024") – calendar year of the activity
  TextColumn get year => text()();

  /// Term (1, 2, or 3) for aggregating hours per term in the summary view
  IntColumn get term => integer()();

  /// Class when the entry was logged – references classes.id
  IntColumn get classId => integer().nullable().references(Classes, #id)();

  /// Study mode when the entry was logged (e.g. "Full-time", "Hybrid")
  TextColumn get studyMode => text().nullable()();

  /// Ministry type (e.g. Community Service, Evangelism)
  TextColumn get ministryType => text()();

  /// Date of the ministry activity
  DateTimeColumn get date => dateTime()();

  /// Hours contributed
  RealColumn get hours => real()();

  /// Supervisor name (optional)
  TextColumn get supervisor => text().nullable()();

  /// Whether the entry has been approved by a supervisor
  BoolColumn get approved => boolean().withDefault(const Constant(false))();

  /// Optional notes
  TextColumn get notes => text().nullable()();

  /// When the record was created
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When the record was last updated
  DateTimeColumn get updatedAt => dateTime().nullable()();

  /// Academic session foreign key for session-based ministry summaries.
  IntColumn get academicSessionId =>
      integer().nullable().references(AcademicSessions, #id)();
}
