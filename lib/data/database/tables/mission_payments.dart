import 'package:drift/drift.dart';

/// Payments toward a mission participation (lump sum or installments).
/// Each row = one payment with date and amount. Paid-to-date = sum; balance = participation.amount - sum.
class MissionPayments extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Mission participation id (references mission_participations.id)
  IntColumn get missionParticipationId => integer()();

  /// Date on which the student made this payment
  DateTimeColumn get paymentDate => dateTime()();

  /// Amount paid in this transaction (Rand)
  RealColumn get amount => real()();

  /// When the record was created
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
