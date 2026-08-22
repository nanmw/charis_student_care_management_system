import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Normalizes [date] to date-only (midnight UTC) for storage/comparison.
DateTime _dateOnly(DateTime date) {
  return DateTime.utc(date.year, date.month, date.day);
}

/// Attendance repository: watch/get/upsert daily attendance by date.
class AttendanceRepository {
  AttendanceRepository(this._db, {void Function()? onLocalChangeSetWritten})
      : _onLocalChangeSetWritten = onLocalChangeSetWritten;

  final AppDatabase _db;
  final void Function()? _onLocalChangeSetWritten;
  static const _uuid = Uuid();

  Future<String> _effectiveChangeSetDeviceId(String? deviceId) async {
    final d = deviceId?.trim();
    if (d != null && d.isNotEmpty && d != 'legacy') return d;
    return SyncFolderConfig.getOrCreateDeviceId();
  }

  Future<String?> _classNameForId(int? classId) async {
    if (classId == null) return null;
    final c = await (_db.select(_db.classes)..where((c) => c.id.equals(classId))).getSingleOrNull();
    return c?.name;
  }

  static Map<String, dynamic> _studentYearEntry(String? name) =>
      (name != null && name.isNotEmpty) ? {'studentYear': name} : {};

  Future<String?> _getSessionCodeById(int? sessionId) async {
    if (sessionId == null) return null;
    try {
      final result = await _db.customSelect(
        'SELECT code FROM academic_sessions WHERE id = ? LIMIT 1',
        variables: [Variable.withInt(sessionId)],
        readsFrom: const {},
      ).getSingleOrNull();
      return result?.data['code'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Stream of attendance rows for [date] (date-only).
  /// When [studentIds] is non-null and non-empty, restrict to those students (for facilitator scope).
  Stream<List<AttendanceData>> watchAttendanceForDate(
    DateTime date, {
    List<int>? studentIds,
  }) {
    final d = _dateOnly(date);
    return (_db.select(_db.attendance)
          ..where((t) {
            var pred = t.date.equals(d);
            if (studentIds != null) {
              if (studentIds.isEmpty) {
                pred = pred & t.studentId.equals(-1);
              } else {
                pred = pred & t.studentId.isIn(studentIds);
              }
            }
            return pred;
          })
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
        if (studentIds != null) {
          if (studentIds.isEmpty) {
            pred = pred & t.studentId.equals(-1);
          } else {
            pred = pred & t.studentId.isIn(studentIds);
          }
        }
        return pred;
      });
    return (query..orderBy([(t) => OrderingTerm.asc(t.studentId)])).get();
  }

  /// Returns the set of distinct dates that have at least one attendance record.
  /// When [studentIds] is null, all dates are returned (admin scope).
  /// When [studentIds] is non-null, only dates with attendance for those students are included;
  /// empty list returns no dates (facilitator with no students).
  Future<Set<DateTime>> getDatesWithAttendance({List<int>? studentIds}) async {
    if (studentIds != null && studentIds.isEmpty) return {};
    var query = _db.select(_db.attendance);
    if (studentIds != null && studentIds.isNotEmpty) {
      query = query..where((t) => t.studentId.isIn(studentIds));
    }
    final rows = await query.get();
    return rows.map((r) => _dateOnly(r.date)).toSet();
  }

  /// Stream of attendance rows whose date is in [[start], [end]] (inclusive, date-only).
  /// When [studentIds] is non-null and non-empty, restrict to those students.
  /// Empty [studentIds] returns no rows (fail-closed for facilitators with no students).
  Stream<List<AttendanceData>> watchAttendanceInRange(
    DateTime start,
    DateTime end, {
    List<int>? studentIds,
  }) {
    final startDay = _dateOnly(start);
    final endDay = _dateOnly(end);
    return (_db.select(_db.attendance)
          ..where((t) {
            var pred = t.date.isBiggerOrEqualValue(startDay) &
                t.date.isSmallerOrEqualValue(endDay);
            if (studentIds != null) {
              if (studentIds.isEmpty) {
                pred = pred & t.studentId.equals(-1);
              } else {
                pred = pred & t.studentId.isIn(studentIds);
              }
            }
            return pred;
          })
          ..orderBy([
            (t) => OrderingTerm.asc(t.date),
            (t) => OrderingTerm.asc(t.studentId),
          ]))
        .watch();
  }

  /// Upserts attendance for [date]. Each entry has studentId + present, notes.
  /// One row per (date, studentId); replaces existing for that date/student.
  /// When [academicSessionId] is provided, set on new rows (session-scoped attendance).
  /// [userId], [deviceId], [userDisplayName], [screen] used for change-set if provided.
  Future<void> upsertAttendanceForDate(
    DateTime date,
    List<AttendanceEntry> rows, {
    required UserRole userRole,
    int? academicSessionId,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) {
    return upsertAttendanceRecords(
      [
        for (final e in rows)
          AttendanceRecordEntry(
            date: date,
            studentId: e.studentId,
            present: e.present,
            notes: e.notes,
          ),
      ],
      userRole: userRole,
      academicSessionId: academicSessionId,
      userId: userId,
      deviceId: deviceId,
      userDisplayName: userDisplayName,
      screen: screen,
    );
  }

  /// Upserts attendance cells across one or more dates in a single transaction.
  /// When [academicSessionId] is provided, set on new rows.
  Future<void> upsertAttendanceRecords(
    List<AttendanceRecordEntry> records, {
    required UserRole userRole,
    int? academicSessionId,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canEnterAttendance(userRole)) {
      throw StateError('Role cannot enter attendance');
    }
    if (records.isEmpty) return;

    final grouped = <DateTime, List<AttendanceRecordEntry>>{};
    for (final r in records) {
      grouped.putIfAbsent(_dateOnly(r.date), () => []).add(r);
    }
    final sessionCode = await _getSessionCodeById(academicSessionId);

    await _db.transaction(() async {
      for (final entry in grouped.entries) {
        await _upsertDateGroupInTransaction(
          date: entry.key,
          rows: entry.value,
          academicSessionId: academicSessionId,
          sessionCode: sessionCode,
          userId: userId,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: screen,
        );
      }
    });
    if (userId != null) {
      _onLocalChangeSetWritten?.call();
    }
  }

  Future<void> _upsertDateGroupInTransaction({
    required DateTime date,
    required List<AttendanceRecordEntry> rows,
    int? academicSessionId,
    String? sessionCode,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    final studentIds = rows.map((e) => e.studentId).toList();
    final existingAttendance = await (_db.select(_db.attendance)
          ..where((t) => t.date.equals(date) & t.studentId.isIn(studentIds)))
        .get();
    final existingMap = {for (final a in existingAttendance) a.studentId: a};

    for (final e in rows) {
      final existing = existingMap[e.studentId];
      final operation = existing != null ? 'UPDATE' : 'INSERT';
      final notesValue = e.notes != null && e.notes!.trim().isNotEmpty
          ? Value(e.notes!.trim())
          : const Value<String?>(null);
      late final int attendanceId;

      if (existing != null) {
        attendanceId = existing.id;
        await (_db.update(_db.attendance)..where((t) => t.id.equals(existing.id)))
            .write(
          AttendanceCompanion(
            present: Value(e.present ? 1 : 0),
            notes: notesValue,
          ),
        );
      } else {
        attendanceId = await _db.into(_db.attendance).insert(
              AttendanceCompanion.insert(
                date: date,
                studentId: e.studentId,
                present: Value(e.present ? 1 : 0),
                notes: notesValue,
                academicSessionId: academicSessionId != null
                    ? Value(academicSessionId)
                    : const Value.absent(),
              ),
            );
      }

      if (userId != null) {
        final studentRow = await (_db.select(_db.students)
              ..where((t) => t.id.equals(e.studentId)))
            .getSingleOrNull();
        final payload = <String, dynamic>{
          'date': date.toIso8601String(),
          'studentId': e.studentId,
          'present': e.present,
          if (e.notes != null && e.notes!.trim().isNotEmpty)
            'notes': e.notes!.trim(),
          if (sessionCode != null) 'academicSession': sessionCode,
          if (studentRow != null)
            'studentName': '${studentRow.surname}, ${studentRow.firstName}',
          if (studentRow != null)
            ..._studentYearEntry(await _classNameForId(studentRow.classId)),
          if (studentRow != null &&
              studentRow.mode != null &&
              studentRow.mode!.isNotEmpty)
            'studentMode': studentRow.mode,
          if (userDisplayName != null) 'userDisplayName': userDisplayName,
          if (screen != null) 'screen': screen,
        };
        await _insertChangeSet(
          table: 'attendance',
          recordId: attendanceId.toString(),
          operation: operation,
          payload: payload,
          userId: userId,
          version: 1,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: screen,
          notifySync: false,
        );
      }
    }
  }

  /// Stream of all attendance records for optional [studentIds] (no date range).
  /// When [studentIds] is null, returns all students (admin scope).
  /// When [studentIds] is empty, returns no rows (fail-closed for facilitators with no students).
  Stream<List<AttendanceData>> watchAttendanceForStudents({
    List<int>? studentIds,
  }) {
    final query = _db.select(_db.attendance);
    if (studentIds != null) {
      if (studentIds.isEmpty) {
        query.where((t) => t.studentId.equals(-1));
      } else {
        query.where((t) => t.studentId.isIn(studentIds));
      }
    }
    query.orderBy([
      (t) => OrderingTerm.asc(t.date),
      (t) => OrderingTerm.asc(t.studentId),
    ]);
    return query.watch();
  }

  /// Stream of all attendance records in the last [days] days.
  /// When [studentIds] is non-null and non-empty, restrict to those students (for facilitator scope).
  /// When [academicSession] is non-null and non-empty, filter by academic_session_id (resolved from code).
  Stream<List<AttendanceData>> watchAttendanceLastDays(
    int days, {
    List<int>? studentIds,
    String? academicSession,
  }) async* {
    final endDate = _dateOnly(DateTime.now());
    final startDate = _dateOnly(endDate.subtract(Duration(days: days - 1)));
    int? sessionId;
    if (academicSession != null && academicSession.trim().isNotEmpty) {
      sessionId = await _getSessionIdByCode(academicSession.trim());
    }
    final stream = (_db.select(_db.attendance)
          ..where((t) {
            var pred = t.date.isBiggerOrEqualValue(startDate) &
                t.date.isSmallerOrEqualValue(endDate);
            if (studentIds != null) {
              if (studentIds.isEmpty) {
                pred = pred & t.studentId.equals(-1);
              } else {
                pred = pred & t.studentId.isIn(studentIds);
              }
            }
            if (sessionId != null) {
              pred = pred & t.academicSessionId.equals(sessionId);
            }
            return pred;
          })
          ..orderBy([(t) => OrderingTerm.asc(t.date), (t) => OrderingTerm.asc(t.studentId)]))
        .watch();
    await for (final list in stream) {
      yield list;
    }
  }

  Future<int?> _getSessionIdByCode(String code) async {
    if (code.trim().isEmpty) return null;
    try {
      final result = await _db.customSelect(
        'SELECT id FROM academic_sessions WHERE code = ? LIMIT 1',
        variables: [Variable.withString(code.trim())],
        readsFrom: const {},
      ).getSingleOrNull();
      return result?.data['id'] as int?;
    } catch (_) {
      return null;
    }
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
    String? deviceId,
    String? userDisplayName,
    String? screen,
    bool notifySync = true,
  }) async {
    final effectiveDeviceId = await _effectiveChangeSetDeviceId(deviceId);
    final fullPayload = Map<String, dynamic>.from(payload);
    if (userDisplayName != null) fullPayload['userDisplayName'] = userDisplayName;
    if (screen != null) fullPayload['screen'] = screen;
    await _db.into(_db.changeSets).insert(
          ChangeSetsCompanion.insert(
            id: _uuid.v4(),
            table: table,
            recordId: recordId,
            operation: operation,
            payload: jsonEncode(fullPayload),
            userId: userId,
            version: version,
            deviceId: effectiveDeviceId,
          ),
        );
    if (notifySync) {
      _onLocalChangeSetWritten?.call();
    }
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

/// One attendance cell across any date (for multi-date upsert).
class AttendanceRecordEntry {
  const AttendanceRecordEntry({
    required this.date,
    required this.studentId,
    required this.present,
    this.notes,
  });

  final DateTime date;
  final int studentId;
  final bool present;
  final String? notes;
}
