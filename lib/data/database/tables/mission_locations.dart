import 'package:drift/drift.dart';

/// Lookup table for mission location names (e.g. "Nairobi, Kenya", "Online").
class MissionLocations extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Location name (e.g. "Nairobi, Kenya")
  TextColumn get name => text()();

  /// Optional description
  TextColumn get description => text().nullable()();

  /// Whether the location is active (soft delete when false)
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
}
