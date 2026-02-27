import 'package:drift/drift.dart';

import 'package:charis_student_care/data/database/app_database.dart';

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

  /// One-time fetch for [studentId] and [year], or null.
  Future<MissionPaymentScheduleData?> getRow(int studentId, String year) async {
    return (_db.select(_db.missionPaymentSchedule)
          ..where((t) =>
              t.studentId.equals(studentId) & t.year.equals(year),)
          ..limit(1))
        .getSingleOrNull();
  }

  /// Batch upserts mission payment rows. [payments] is studentId -> MissionPaymentData.
  Future<int> batchUpsertMissionPayments({
    required String year,
    required Map<int, MissionPaymentData> payments,
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
