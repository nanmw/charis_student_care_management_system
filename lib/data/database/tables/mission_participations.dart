import 'package:drift/drift.dart';

/// Mission participations: one row per student sign-up per mission.
/// Unique on (mission_id, student_id).
class MissionParticipations extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Mission id (references missions.id)
  IntColumn get missionId => integer()();

  /// Student id (references students.id)
  IntColumn get studentId => integer()();

  /// Role (e.g. "Translator", "Volunteer", "Mentor")
  TextColumn get role => text()();

  /// Total amount the student will pay for this trip (Rand)
  RealColumn get amount => real().withDefault(const Constant(0))();

  /// When the record was created
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
        'UNIQUE(mission_id, student_id)',
      ];
}
