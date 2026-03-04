import 'package:drift/drift.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/academic_session_repository.dart';

/// DTO for mission payment batch upsert.
class MissionPaymentData {
  MissionPaymentData({
    this.tripSelected,
    DateTime? date,
    this.amount = 0,
    this.mar = 0,
    this.apr = 0,
    this.may = 0,
    this.jun = 0,
    this.jul = 0,
    this.aug = 0,
    this.sep = 0,
    this.oct = 0,
    this.comment,
  }) : date = date?.millisecondsSinceEpoch;

  final String? tripSelected;
  final int? date; // epoch milliseconds
  final double amount;
  final double mar;
  final double apr;
  final double may;
  final double jun;
  final double jul;
  final double aug;
  final double sep;
  final double oct;
  final String? comment;
}

/// Mission payment schedule repository: watch/upsert by student and year.
class MissionPaymentRepository {
  MissionPaymentRepository(this._db);

  final AppDatabase _db;

  /// Stream of mission payment schedule rows for [year], ordered by studentId.
  Stream<List<MissionPaymentScheduleData>> watchForYear(String year) {
    return (_db.select(_db.missionPaymentSchedule)
          ..where((t) => t.year.equals(year))
          ..orderBy([(t) => OrderingTerm.asc(t.studentId)]))
        .watch();
  }

  /// Stream of mission payment schedule rows for the given academic [sessionCode].
  /// Backward compatibility: prefer academic_session_id; include legacy rows where
  /// academic_session_id is null but year matches the session's start year.
  Stream<List<MissionPaymentScheduleData>> watchForSession(String sessionCode) async* {
    final sessionId = await _getSessionIdByCode(sessionCode);
    final legacyYear = AcademicSessionRepository.yearFromSessionCode(sessionCode);
    final all = _db.select(_db.missionPaymentSchedule).watch();
    await for (final list in all) {
      var filtered = list;
      if (sessionId != null && legacyYear != null) {
        filtered = filtered.where((r) =>
            r.academicSessionId == sessionId ||
            (r.academicSessionId == null && r.year == legacyYear),).toList();
      } else if (sessionId != null) {
        filtered = filtered.where((r) => r.academicSessionId == sessionId).toList();
      } else if (legacyYear != null) {
        filtered = filtered.where((r) => r.year == legacyYear).toList();
      } else {
        filtered = [];
      }
      filtered.sort((a, b) => a.studentId.compareTo(b.studentId));
      yield filtered;
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

  /// One-time fetch for [studentId] and [year], or null.
  Future<MissionPaymentScheduleData?> getRow(int studentId, String year) async {
    return (_db.select(_db.missionPaymentSchedule)
          ..where((t) =>
              t.studentId.equals(studentId) & t.year.equals(year),)
          ..limit(1))
        .getSingleOrNull();
  }

  /// Batch upserts mission payment rows. [payments] is studentId -> MissionPaymentData.
  /// When [academicSessionId] is provided, sets academic_session_id on new rows.
  Future<int> batchUpsertMissionPayments({
    required String year,
    required Map<int, MissionPaymentData> payments,
    int? academicSessionId,
    String? userId,
  }) async {
    if (payments.isEmpty) return 0;

    final studentIds = payments.keys.toList();
    final existing = await (_db.select(_db.missionPaymentSchedule)
          ..where((t) =>
              t.year.equals(year) & t.studentId.isIn(studentIds),))
        .get();
    final existingMap = {for (final r in existing) r.studentId: r};

    return await _db.transaction(() async {
      int count = 0;
      for (final entry in payments.entries) {
        final studentId = entry.key;
        final data = entry.value;
        final row = existingMap[studentId];

        if (row != null) {
          await (_db.update(_db.missionPaymentSchedule)
                ..where((t) => t.id.equals(row.id)))
              .write(
            MissionPaymentScheduleCompanion(
              tripSelected: Value(data.tripSelected),
              date: Value(data.date),
              amount: Value(data.amount),
              mar: Value(data.mar),
              apr: Value(data.apr),
              may: Value(data.may),
              jun: Value(data.jun),
              jul: Value(data.jul),
              aug: Value(data.aug),
              sep: Value(data.sep),
              oct: Value(data.oct),
              comment: Value(data.comment),
            ),
          );
        } else {
          await _db.into(_db.missionPaymentSchedule).insert(
            MissionPaymentScheduleCompanion.insert(
              studentId: studentId,
              year: year,
              academicSessionId: academicSessionId != null ? Value(academicSessionId) : const Value.absent(),
              tripSelected: Value(data.tripSelected),
              date: Value(data.date),
              amount: Value(data.amount),
              mar: Value(data.mar),
              apr: Value(data.apr),
              may: Value(data.may),
              jun: Value(data.jun),
              jul: Value(data.jul),
              aug: Value(data.aug),
              sep: Value(data.sep),
              oct: Value(data.oct),
              comment: Value(data.comment),
            ),
          );
        }
        count++;
      }
      return count;
    });
  }
}
