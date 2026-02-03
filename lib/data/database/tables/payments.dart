import 'package:drift/drift.dart';

/// Payments table: one row per student per payment year.
/// Stores monthly amounts (Jan–Dec) and lump sum; total paid = sum(months) + lump_sum.
class Payments extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Student id (references students.id)
  IntColumn get studentId => integer()();

  /// Payment year (e.g. "2026") for which Jan–Dec apply
  TextColumn get year => text()();

  /// Monthly amounts in Rand (default 0)
  RealColumn get jan => real().withDefault(const Constant(0))();
  RealColumn get feb => real().withDefault(const Constant(0))();
  RealColumn get mar => real().withDefault(const Constant(0))();
  RealColumn get apr => real().withDefault(const Constant(0))();
  RealColumn get may => real().withDefault(const Constant(0))();
  RealColumn get jun => real().withDefault(const Constant(0))();
  RealColumn get jul => real().withDefault(const Constant(0))();
  RealColumn get aug => real().withDefault(const Constant(0))();
  RealColumn get sep => real().withDefault(const Constant(0))();
  RealColumn get oct => real().withDefault(const Constant(0))();
  RealColumn get nov => real().withDefault(const Constant(0))();
  RealColumn get dec => real().withDefault(const Constant(0))();

  /// Lump sum amount in Rand (default 0)
  RealColumn get lumpSum => real().withDefault(const Constant(0))();

  /// Timestamp when record was created
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Timestamp when record was last updated
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {studentId, year},
      ];
}
