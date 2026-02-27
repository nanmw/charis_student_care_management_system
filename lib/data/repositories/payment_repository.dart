import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/data/database/app_database.dart';

/// Payment data for batch operations
class PaymentData {
  PaymentData({
    this.jan = 0,
    this.feb = 0,
    this.mar = 0,
    this.apr = 0,
    this.may = 0,
    this.jun = 0,
    this.jul = 0,
    this.aug = 0,
    this.sep = 0,
    this.oct = 0,
    this.nov = 0,
    this.dec = 0,
    this.lumpSum = 0,
  });

  final double jan;
  final double feb;
  final double mar;
  final double apr;
  final double may;
  final double jun;
  final double jul;
  final double aug;
  final double sep;
  final double oct;
  final double nov;
  final double dec;
  final double lumpSum;
}

/// Payment repository: watch/upsert payment rows by student and year.
class PaymentRepository {
  PaymentRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  Future<String?> _classNameForId(int? classId) async {
    if (classId == null) return null;
    final c = await (_db.select(_db.classes)..where((c) => c.id.equals(classId))).getSingleOrNull();
    return c?.name;
  }

  static Map<String, dynamic> _studentYearEntry(String? name) =>
      (name != null && name.isNotEmpty) ? {'studentYear': name} : {};

  /// Stream of payment rows for [year]. Use for reactive UI.
  /// When [studentIds] is non-null and non-empty, restrict to those students (e.g. facilitator scope for dashboard/student summary view).
  Stream<List<Payment>> watchPaymentsForYear(String year, {List<int>? studentIds}) {
    return (_db.select(_db.payments)
          ..where((t) {
            var pred = t.year.equals(year);
            if (studentIds != null && studentIds.isNotEmpty) {
              pred = pred & t.studentId.isIn(studentIds);
            }
            return pred;
          })
          ..orderBy([(t) => OrderingTerm.asc(t.studentId)]))
        .watch();
  }

  /// One-time fetch of payment row for [studentId] and [year], or null if none.
  Future<Payment?> getPaymentRow(int studentId, String year) async {
    return (_db.select(_db.payments)
          ..where((t) =>
              t.studentId.equals(studentId) & t.year.equals(year),)
          ..limit(1))
        .getSingleOrNull();
  }

  /// Upserts a payment row for [studentId] and [year]. Replaces existing row if present.
  /// [userId], [deviceId], [userDisplayName], [screen] used for change-set if provided.
  Future<void> upsertPaymentRow({
    required int studentId,
    required String year,
    double jan = 0,
    double feb = 0,
    double mar = 0,
    double apr = 0,
    double may = 0,
    double jun = 0,
    double jul = 0,
    double aug = 0,
    double sep = 0,
    double oct = 0,
    double nov = 0,
    double dec = 0,
    double lumpSum = 0,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    final existing = await getPaymentRow(studentId, year);
    final now = DateTime.now();
    final operation = existing != null ? 'UPDATE' : 'INSERT';
    final paymentId = existing?.id;
    
    if (existing != null) {
      await (_db.update(_db.payments)..where((t) => t.id.equals(existing.id)))
          .write(
        PaymentsCompanion(
          jan: Value(jan),
          feb: Value(feb),
          mar: Value(mar),
          apr: Value(apr),
          may: Value(may),
          jun: Value(jun),
          jul: Value(jul),
          aug: Value(aug),
          sep: Value(sep),
          oct: Value(oct),
          nov: Value(nov),
          dec: Value(dec),
          lumpSum: Value(lumpSum),
          updatedAt: Value(now),
        ),
      );
    } else {
      final inserted = await _db.into(_db.payments).insert(
        PaymentsCompanion.insert(
          studentId: studentId,
          year: year,
          jan: Value(jan),
          feb: Value(feb),
          mar: Value(mar),
          apr: Value(apr),
          may: Value(may),
          jun: Value(jun),
          jul: Value(jul),
          aug: Value(aug),
          sep: Value(sep),
          oct: Value(oct),
          nov: Value(nov),
          dec: Value(dec),
          lumpSum: Value(lumpSum),
          createdAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      if (userId != null) {
        final studentRow = await (_db.select(_db.students)..where((t) => t.id.equals(studentId))).getSingleOrNull();
        final payload = <String, dynamic>{
          'studentId': studentId,
          'year': year,
          'jan': jan,
          'feb': feb,
          'mar': mar,
          'apr': apr,
          'may': may,
          'jun': jun,
          'jul': jul,
          'aug': aug,
          'sep': sep,
          'oct': oct,
          'nov': nov,
          'dec': dec,
          'lumpSum': lumpSum,
          if (studentRow != null) 'studentName': '${studentRow.surname}, ${studentRow.firstName}',
          if (studentRow != null) ..._studentYearEntry(await _classNameForId(studentRow.classId)),
          if (studentRow != null && studentRow.mode != null && studentRow.mode!.isNotEmpty) 'studentMode': studentRow.mode,
          if (userDisplayName != null) 'userDisplayName': userDisplayName,
          if (screen != null) 'screen': screen,
        };
        await _insertChangeSet(
          table: 'payments',
          recordId: inserted.toString(),
          operation: operation,
          payload: payload,
          userId: userId,
          version: 1,
          deviceId: deviceId ?? 'legacy',
          userDisplayName: userDisplayName,
          screen: screen,
        );
      }
      return;
    }
    
    if (userId != null && paymentId != null) {
      final studentRow = await (_db.select(_db.students)..where((t) => t.id.equals(studentId))).getSingleOrNull();
      final payload = <String, dynamic>{
        'studentId': studentId,
        'year': year,
        'jan': jan,
        'feb': feb,
        'mar': mar,
        'apr': apr,
        'may': may,
        'jun': jun,
        'jul': jul,
        'aug': aug,
        'sep': sep,
        'oct': oct,
        'nov': nov,
        'dec': dec,
        'lumpSum': lumpSum,
        if (studentRow != null) 'studentName': '${studentRow.surname}, ${studentRow.firstName}',
        if (studentRow != null) ..._studentYearEntry(await _classNameForId(studentRow.classId)),
        if (studentRow != null && studentRow.mode != null && studentRow.mode!.isNotEmpty) 'studentMode': studentRow.mode,
        if (userDisplayName != null) 'userDisplayName': userDisplayName,
        if (screen != null) 'screen': screen,
      };
      await _insertChangeSet(
        table: 'payments',
        recordId: paymentId.toString(),
        operation: operation,
        payload: payload,
        userId: userId,
        version: 1,
        deviceId: deviceId ?? 'legacy',
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  /// Batch upserts multiple payment rows efficiently in a single transaction.
  /// This is much faster than calling upsertPaymentRow multiple times.
  /// [payments] is a map of studentId -> PaymentData.
  /// [userId], [deviceId], [userDisplayName], [screen] used for change-set if provided.
  Future<int> batchUpsertPayments({
    required String year,
    required Map<int, PaymentData> payments,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (payments.isEmpty) return 0;

    final studentIds = payments.keys.toList();
    final now = DateTime.now();

    // Fetch all existing payment rows for these students and year in one query
    final existingPayments = await (_db.select(_db.payments)
          ..where((t) =>
              t.year.equals(year) & t.studentId.isIn(studentIds),))
        .get();

    final existingMap = {for (final p in existingPayments) p.studentId: p};

    // Use a transaction to batch all operations
    return await _db.transaction(() async {
      int count = 0;

      for (final entry in payments.entries) {
        final studentId = entry.key;
        final payment = entry.value;
        final existing = existingMap[studentId];
        final operation = existing != null ? 'UPDATE' : 'INSERT';
        int? paymentId;

        if (existing != null) {
          // Update existing row
          paymentId = existing.id;
          await (_db.update(_db.payments)..where((t) => t.id.equals(existing.id)))
              .write(
            PaymentsCompanion(
              jan: Value(payment.jan),
              feb: Value(payment.feb),
              mar: Value(payment.mar),
              apr: Value(payment.apr),
              may: Value(payment.may),
              jun: Value(payment.jun),
              jul: Value(payment.jul),
              aug: Value(payment.aug),
              sep: Value(payment.sep),
              oct: Value(payment.oct),
              nov: Value(payment.nov),
              dec: Value(payment.dec),
              lumpSum: Value(payment.lumpSum),
              updatedAt: Value(now),
            ),
          );
        } else {
          // Insert new row
          paymentId = await _db.into(_db.payments).insert(
            PaymentsCompanion.insert(
              studentId: studentId,
              year: year,
              jan: Value(payment.jan),
              feb: Value(payment.feb),
              mar: Value(payment.mar),
              apr: Value(payment.apr),
              may: Value(payment.may),
              jun: Value(payment.jun),
              jul: Value(payment.jul),
              aug: Value(payment.aug),
              sep: Value(payment.sep),
              oct: Value(payment.oct),
              nov: Value(payment.nov),
              dec: Value(payment.dec),
              lumpSum: Value(payment.lumpSum),
              createdAt: Value(now),
              updatedAt: Value(now),
            ),
          );
        }
        
        if (userId != null) {
          final studentRow = await (_db.select(_db.students)..where((t) => t.id.equals(studentId))).getSingleOrNull();
          final payload = <String, dynamic>{
            'studentId': studentId,
            'year': year,
            'jan': payment.jan,
            'feb': payment.feb,
            'mar': payment.mar,
            'apr': payment.apr,
            'may': payment.may,
            'jun': payment.jun,
            'jul': payment.jul,
            'aug': payment.aug,
            'sep': payment.sep,
            'oct': payment.oct,
            'nov': payment.nov,
            'dec': payment.dec,
            'lumpSum': payment.lumpSum,
            if (studentRow != null) 'studentName': '${studentRow.surname}, ${studentRow.firstName}',
            if (studentRow != null) ..._studentYearEntry(await _classNameForId(studentRow.classId)),
            if (studentRow != null && studentRow.mode != null && studentRow.mode!.isNotEmpty) 'studentMode': studentRow.mode,
            if (userDisplayName != null) 'userDisplayName': userDisplayName,
            if (screen != null) 'screen': screen,
          };
          await _insertChangeSet(
            table: 'payments',
            recordId: paymentId.toString(),
            operation: operation,
            payload: payload,
            userId: userId,
            version: 1,
            deviceId: deviceId ?? 'legacy',
            userDisplayName: userDisplayName,
            screen: screen,
          );
        }
        count++;
      }

      return count;
    });
  }

  /// Calculates total paid amount for [year] across all payments.
  Stream<double> watchTotalPaidForYear(String year) {
    final totalPaidExpr = _db.payments.jan +
        _db.payments.feb +
        _db.payments.mar +
        _db.payments.apr +
        _db.payments.may +
        _db.payments.jun +
        _db.payments.jul +
        _db.payments.aug +
        _db.payments.sep +
        _db.payments.oct +
        _db.payments.nov +
        _db.payments.dec +
        _db.payments.lumpSum;

    return (_db.selectOnly(_db.payments)
          ..addColumns([totalPaidExpr.sum()])
          ..where(_db.payments.year.equals(year))
          ..groupBy([]))
        .watch()
        .map((rows) => rows.isNotEmpty
            ? (rows.single.read<double>(totalPaidExpr.sum()) ?? 0.0)
            : 0.0,);
  }

  Future<void> _insertChangeSet({
    required String table,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    required String userId,
    required int version,
    required String deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
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
            deviceId: deviceId,
          ),
        );
  }
}
