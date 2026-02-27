import 'package:drift/drift.dart';

/// Mission payment schedule: one row per student per schedule year.
/// Tracks trip selection, total amount, monthly payments (Mar–Oct), and comment.
/// Paid to date and balance are computed (sum of months; amount − sum).
class MissionPaymentSchedule extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Student id (references students.id)
  IntColumn get studentId => integer()();

  /// Schedule year (e.g. "2026") for which this schedule applies
  TextColumn get year => text()();

  /// Trip selected (e.g. mission trip name)
  TextColumn get tripSelected => text().nullable()();

  /// Date (epoch milliseconds), e.g. trip or selection date
  IntColumn get date => integer().nullable()();

  /// Total amount due in Rand (default 0)
  RealColumn get amount => real().withDefault(const Constant(0))();

  /// Monthly amounts Mar–Oct in Rand (default 0)
  RealColumn get mar => real().withDefault(const Constant(0))();
  RealColumn get apr => real().withDefault(const Constant(0))();
  RealColumn get may => real().withDefault(const Constant(0))();
  RealColumn get jun => real().withDefault(const Constant(0))();
  RealColumn get jul => real().withDefault(const Constant(0))();
  RealColumn get aug => real().withDefault(const Constant(0))();
  RealColumn get sep => real().withDefault(const Constant(0))();
  RealColumn get oct => real().withDefault(const Constant(0))();

  /// Comment or notes
  TextColumn get comment => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {studentId, year},
      ];
}
