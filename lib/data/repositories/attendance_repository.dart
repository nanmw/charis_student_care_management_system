import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/data/database/app_database.dart';

/// Normalizes [date] to date-only (midnight UTC) for storage/comparison.
DateTime _dateOnly(DateTime date) {
  return DateTime.utc(date.year, date.month, date.day);
}

/// Attendance repository: watch/get/upsert daily attendance by date.
class AttendanceRepository {
  AttendanceRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

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
    List<AttendanceEntry> rows, {
    String? userId,
  }) async {
    if (rows.isEmpty) return;
    
    final d = _dateOnly(date);
    final studentIds = rows.map((e) => e.studentId).toList();

    // Fetch all existing attendance rows for this date and students in one query
    final existingAttendance = await (_db.select(_db.attendance)
          ..where((t) =>
              t.date.equals(d) & t.studentId.isIn(studentIds),))
        .get();

    final existingMap = {for (final a in existingAttendance) a.studentId: a};

    // Use a transaction to batch all operations
    await _db.transaction(() async {
      for (final e in rows) {
        final existing = existingMap[e.studentId];
        final operation = existing != null ? 'UPDATE' : 'INSERT';
        int? attendanceId;

        if (existing != null) {
          // Update existing record
          attendanceId = existing.id;
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
          attendanceId = await _db.into(_db.attendance).insert(
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
        
        if (userId != null) {
          await _insertChangeSet(
            table: 'attendance',
            recordId: attendanceId.toString(),
            operation: operation,
            payload: {
              'date': d.toIso8601String(),
              'studentId': e.studentId,
              'present': e.present,
              if (e.notes != null && e.notes!.trim().isNotEmpty) 'notes': e.notes!.trim(),
            },
            userId: userId,
            version: 1,
          );
        }
      }
    });
  }

  /// Calculates average attendance percentage for the last [days] days.
  /// Computes per-student percentages then averages them.
  /// Returns null if no attendance data exists.
  Stream<double?> watchAverageAttendancePercentage({int days = 30}) {
    final endDate = _dateOnly(DateTime.now());
    final startDate = _dateOnly(endDate.subtract(Duration(days: days - 1)));

    // Fetch all attendance records and filter by date range in memory
    // This is simpler than trying to use date range queries in Drift
    return _db.select(_db.attendance).watch().map((allRecords) {
      // Filter records within date range (inclusive on both ends)
      final attendanceRecords = allRecords.where((record) {
        final recordDate = _dateOnly(record.date);
        return !recordDate.isBefore(startDate) && !recordDate.isAfter(endDate);
      }).toList();
      
      if (attendanceRecords.isEmpty) return null;
      
      // Group by studentId
      final Map<int, List<AttendanceData>> byStudent = {};
      for (final record in attendanceRecords) {
        byStudent.putIfAbsent(record.studentId, () => []).add(record);
      }
      
      if (byStudent.isEmpty) return null;
      
      // Calculate percentage for each student
      final List<double> studentPercentages = [];
      for (final studentRecords in byStudent.values) {
        final totalDays = studentRecords.length;
        if (totalDays == 0) continue;
        
        final presentDays = studentRecords.where((r) => r.present == 1).length;
        final percentage = (presentDays / totalDays) * 100;
        studentPercentages.add(percentage);
      }
      
      if (studentPercentages.isEmpty) return null;
      
      // Average the percentages
      final sum = studentPercentages.fold<double>(0.0, (a, b) => a + b);
      return sum / studentPercentages.length;
    });
  }

  Future<void> _insertChangeSet({
    required String table,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    required String userId,
    required int version,
  }) async {
    await _db.into(_db.changeSets).insert(
          ChangeSetsCompanion.insert(
            id: _uuid.v4(),
            table: table,
            recordId: recordId,
            operation: operation,
            payload: jsonEncode(payload),
            userId: userId,
            version: version,
          ),
        );
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
