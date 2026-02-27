import 'package:drift/drift.dart';

/// Mission opportunities: one row per mission (e.g. Project Hope Africa).
class Missions extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Mission title (e.g. "Project Hope Africa")
  TextColumn get title => text()();

  /// Location (e.g. "Nairobi, Kenya", "Online")
  TextColumn get location => text()();

  /// Start date of the mission
  DateTimeColumn get startDate => dateTime()();

  /// End date of the mission
  DateTimeColumn get endDate => dateTime()();

  /// Total number of participant slots
  IntColumn get slotsTotal => integer()();

  /// Optional description
  TextColumn get description => text().nullable()();

  /// Whether the mission is active (soft delete when false)
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Year for filtering (e.g. "2025")
  TextColumn get year => text()();

  /// Default trip cost in Rand (pre-fills participation amount; nullable)
  RealColumn get amount => real().nullable()();

  /// Target student mode: 'Full-time', 'Hybrid', or 'Both'. Required.
  TextColumn get mode => text()();

  /// When the record was created
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When the record was last updated
  DateTimeColumn get updatedAt => dateTime().nullable()();
}
