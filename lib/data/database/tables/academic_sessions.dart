import 'package:drift/drift.dart';

/// Academic sessions table: one academic session = one calendar year Feb–Oct (e.g. code "2026").
class AcademicSessions extends Table {
  /// Auto-incrementing primary key.
  IntColumn get id => integer().autoIncrement()();

  /// Unique session code, e.g. "2026" (single year; legacy "2024-2025" still supported).
  TextColumn get code => text().unique()();

  /// Optional start date for the session (Unix timestamp in seconds or millis, depending on usage).
  IntColumn get startDate => integer().nullable()();

  /// Optional end date for the session.
  IntColumn get endDate => integer().nullable()();

  /// Whether this session is currently active. At most one row should be active.
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();

  /// Optional human-friendly display name.
  TextColumn get displayName => text().nullable()();
}

