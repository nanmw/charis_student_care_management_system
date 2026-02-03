import 'package:drift/drift.dart';

import 'package:charis_student_care/data/database/app_database.dart';

// #region agent log (disabled for performance - synchronous file I/O was blocking UI)
void _debugLog(String location, String message, Map<String, dynamic> data, String hypothesisId) {
  // No-op: was causing UI jank due to synchronous file writes during attendance upsert.
}
// #endregion

/// Normalizes [date] to date-only (midnight UTC) for storage/comparison.
DateTime _dateOnly(DateTime date) {
  return DateTime.utc(date.year, date.month, date.day);
}

/// Attendance repository: watch/get/upsert daily attendance by date.
class AttendanceRepository {
  AttendanceRepository(this._db);

  final AppDatabase _db;

  /// Stream of attendance rows for [date] (date-only).
  Stream<List<AttendanceData>> watchAttendanceForDate(DateTime date) {
    final d = _dateOnly(date);
    return (_db.select(_db.attendance)
          ..where((t) => t.date.equals(d))
          ..orderBy([(t) => OrderingTerm.asc(t.studentId)]))
        .watch();
  }

  /// One-time fetch of attendance rows for [date] and optional [studentIds].
  Future<List<AttendanceData>> getAttendanceForDateAndStudents(
    DateTime date, [
    List<int>? studentIds,
  ]) async {
    final d = _dateOnly(date);
    var query = _db.select(_db.attendance)
      ..where((t) {
        var pred = t.date.equals(d);
        if (studentIds != null && studentIds.isNotEmpty) {
          pred = pred & t.studentId.isIn(studentIds);
        }
        return pred;
      });
    return (query..orderBy([(t) => OrderingTerm.asc(t.studentId)])).get();
  }

  /// Upserts attendance for [date]. Each entry has studentId + present, notes.
  /// One row per (date, studentId); replaces existing for that date/student.
  /// Optimized to use batch operations for better performance.
  Future<void> upsertAttendanceForDate(
    DateTime date,
    List<AttendanceEntry> rows,
  ) async {
    if (rows.isEmpty) return;
    
    final d = _dateOnly(date);
    final studentIds = rows.map((e) => e.studentId).toList();

    // Fetch all existing attendance rows for this date and students in one query
    final existingAttendance = await (_db.select(_db.attendance)
          ..where((t) =>
              t.date.equals(d) & t.studentId.isIn(studentIds)))
        .get();

    final existingMap = {for (final a in existingAttendance) a.studentId: a};

    // Use a transaction to batch all operations
    await _db.transaction(() async {
      for (final e in rows) {
        final existing = existingMap[e.studentId];

        if (existing != null) {
          // Update existing record
          await (_db.update(_db.attendance)..where((t) => t.id.equals(existing.id))).write(
            AttendanceCompanion(
              present: Value(e.present ? 1 : 0),
              notes: e.notes != null && e.notes!.trim().isNotEmpty
                  ? Value(e.notes!.trim())
                  : const Value.absent(),
            ),
          );
        } else {
          // Insert new record
          await _db.into(_db.attendance).insert(
            AttendanceCompanion.insert(
              date: d,
              studentId: e.studentId,
              present: Value(e.present ? 1 : 0),
              notes: e.notes != null && e.notes!.trim().isNotEmpty
                  ? Value(e.notes!.trim())
                  : const Value.absent(),
            ),
          );
        }
      }
    });
  }
}

/// In-memory entry for one student's attendance on a date (for upsert).
class AttendanceEntry {
  const AttendanceEntry({
    required this.studentId,
    required this.present,
    this.notes,
  });

  final int studentId;
  final bool present;
  final String? notes;
}
