import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/academic_session_repository.dart';

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
  PaymentRepository(this._db, {void Function()? onLocalChangeSetWritten})
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

  /// Stream of payment rows for [year]. Use for reactive UI.
  /// When [studentIds] is non-null and non-empty, restrict to those students (e.g. facilitator scope for dashboard/student summary view).
  Stream<List<Payment>> watchPaymentsForYear(String year, {List<int>? studentIds}) {
    return (_db.select(_db.payments)
          ..where((t) {
            var pred = t.year.equals(year);
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

  /// Stream of payment rows for the given academic [sessionCode].
  /// Resolves session ID and returns rows where academic_session_id matches, or where year matches the session start year (legacy).
  /// When [studentIds] is non-null and non-empty, restricts to those students.
  Stream<List<Payment>> watchPaymentsForSession(String sessionCode, {List<int>? studentIds}) {
    return _watchPaymentsBySessionOrYear(sessionCode, studentIds);
  }

  /// Backward compatibility: prefer academic_session_id; include legacy rows where
  /// academic_session_id is null but year matches the session's start year.
  Stream<List<Payment>> _watchPaymentsBySessionOrYear(String sessionCode, List<int>? studentIds) async* {
    final sessionId = await _getSessionIdByCode(sessionCode);
    final legacyYear = AcademicSessionRepository.yearFromSessionCode(sessionCode);
    final allPayments = _db.select(_db.payments).watch();
    await for (final list in allPayments) {
      var filtered = list;
      if (sessionId != null && legacyYear != null) {
        filtered = filtered.where((p) =>
            p.academicSessionId == sessionId ||
            (p.academicSessionId == null && p.year == legacyYear),).toList();
      } else if (sessionId != null) {
        filtered = filtered.where((p) => p.academicSessionId == sessionId).toList();
      } else if (legacyYear != null) {
        filtered = filtered.where((p) => p.year == legacyYear).toList();
      } else {
        filtered = [];
      }
      if (studentIds != null) {
        if (studentIds.isEmpty) {
          filtered = <Payment>[];
        } else {
          final idSet = studentIds.toSet();
          filtered = filtered.where((p) => idSet.contains(p.studentId)).toList();
        }
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

  /// One-time fetch of payment row for [studentId] and [year], or null if none.
  Future<Payment?> getPaymentRow(int studentId, String year) async {
    return (_db.select(_db.payments)
          ..where((t) =>
              t.studentId.equals(studentId) & t.year.equals(year),)
          ..limit(1))
        .getSingleOrNull();
  }

  /// One-time fetch of payment row for [studentId] and [sessionCode], or null if none.
  /// Resolves session and matches by academic_session_id or by year derived from session.
  Future<Payment?> getPaymentRowForSession(int studentId, String sessionCode) async {
    final sessionId = await _getSessionIdByCode(sessionCode);
    final legacyYear = AcademicSessionRepository.yearFromSessionCode(sessionCode);
    final list = await (_db.select(_db.payments)..where((t) => t.studentId.equals(studentId))).get();
    if (sessionId != null) {
      final matches = list.where((p) => p.academicSessionId == sessionId);
      if (matches.isNotEmpty) return matches.first;
    }
    if (legacyYear != null) {
      final matches = list.where((p) => p.year == legacyYear);
      if (matches.isNotEmpty) return matches.first;
    }
    return null;
  }

  /// Upserts a payment row for [studentId] and [year]. Replaces existing row if present.
  /// When [academicSessionId] is provided, also sets the academic_session_id column.
  /// [userId], [deviceId], [userDisplayName], [screen] used for change-set if provided.
  Future<void> upsertPaymentRow({
    required int studentId,
    required String year,
    int? academicSessionId,
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
    required UserRole userRole,
  }) async {
    if (!RolePermissions.canManageFinancials(userRole)) {
      throw StateError('Role cannot manage financials');
    }
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
          academicSessionId: academicSessionId != null ? Value(academicSessionId) : const Value.absent(),
        ),
      );
    } else {
      final inserted = await _db.into(_db.payments).insert(
        PaymentsCompanion.insert(
          studentId: studentId,
          year: year,
          academicSessionId: academicSessionId != null ? Value(academicSessionId) : const Value.absent(),
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
        final sessionCode = await _getSessionCodeById(academicSessionId) ?? year;
        final payload = <String, dynamic>{
          'studentId': studentId,
          'year': year,
          'academicSession': sessionCode,
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
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: screen,
        );
      }
      return;
    }
    
    if (userId != null && paymentId != null) {
      final studentRow = await (_db.select(_db.students)..where((t) => t.id.equals(studentId))).getSingleOrNull();
      final sessionCode = await _getSessionCodeById(academicSessionId) ?? year;
      final payload = <String, dynamic>{
        'studentId': studentId,
        'year': year,
        'academicSession': sessionCode,
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
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  /// Batch upserts multiple payment rows efficiently in a single transaction.
  /// This is much faster than calling upsertPaymentRow multiple times.
  /// [payments] is a map of studentId -> PaymentData.
  /// When [academicSessionId] is provided, sets academic_session_id on new/updated rows.
  /// [userId], [deviceId], [userDisplayName], [screen] used for change-set if provided.
  Future<int> batchUpsertPayments({
    required String year,
    required Map<int, PaymentData> payments,
    int? academicSessionId,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
    required UserRole userRole,
  }) async {
    if (!RolePermissions.canManageFinancials(userRole)) {
      throw StateError('Role cannot manage financials');
    }
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
    final count = await _db.transaction(() async {
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
              academicSessionId: academicSessionId != null ? Value(academicSessionId) : const Value.absent(),
            ),
          );
        } else {
          // Insert new row
          paymentId = await _db.into(_db.payments).insert(
            PaymentsCompanion.insert(
              studentId: studentId,
              year: year,
              academicSessionId: academicSessionId != null ? Value(academicSessionId) : const Value.absent(),
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
          final sessionCode = await _getSessionCodeById(academicSessionId) ?? year;
          final payload = <String, dynamic>{
            'studentId': studentId,
            'year': year,
            'academicSession': sessionCode,
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
            deviceId: deviceId,
            userDisplayName: userDisplayName,
            screen: screen,
            notifySync: false,
          );
        }
        count++;
      }

      return count;
    });
    if (userId != null && count > 0) {
      _onLocalChangeSetWritten?.call();
    }
    return count;
  }

  /// Calculates session total paid for [year] (Feb–Oct + lump sum; excludes Jan/Nov/Dec).
  Stream<double> watchTotalPaidForYear(String year) {
    final totalPaidExpr = _db.payments.feb +
        _db.payments.mar +
        _db.payments.apr +
        _db.payments.may +
        _db.payments.jun +
        _db.payments.jul +
        _db.payments.aug +
        _db.payments.sep +
        _db.payments.oct +
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

  /// Calculates session total paid for [sessionCode] (Feb–Oct + lump sum).
  /// Uses academic_session_id when available, otherwise year derived from session.
  Stream<double> watchTotalPaidForSession(String sessionCode) async* {
    final sessionId = await _getSessionIdByCode(sessionCode);
    final legacyYear = AcademicSessionRepository.yearFromSessionCode(sessionCode);
    final totalPaidExpr = _db.payments.feb +
        _db.payments.mar +
        _db.payments.apr +
        _db.payments.may +
        _db.payments.jun +
        _db.payments.jul +
        _db.payments.aug +
        _db.payments.sep +
        _db.payments.oct +
        _db.payments.lumpSum;
    if (sessionId == null && legacyYear == null) {
      yield 0.0;
      return;
    }
    final stream = sessionId != null
        ? (_db.selectOnly(_db.payments)
              ..addColumns([totalPaidExpr.sum()])
              ..where(_db.payments.academicSessionId.equals(sessionId))
              ..groupBy([]))
            .watch()
        : (_db.selectOnly(_db.payments)
              ..addColumns([totalPaidExpr.sum()])
              ..where(_db.payments.year.equals(legacyYear!))
              ..groupBy([]))
            .watch();
    yield* stream.map((rows) => rows.isNotEmpty
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
