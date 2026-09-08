import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/app_settings_repository.dart';
import 'package:charis_student_care/data/services/change_set_sync_service.dart';

/// Applies a single change-set to the local DB and records it in change_sets.
/// Maintains a mapping of (table:remoteRecordId) -> localId for INSERT/UPDATE/DELETE.
/// For critical tables (payments, students status) detects conflicts and returns [ApplyResultConflict].
class ChangeSetApplier {
  ChangeSetApplier(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  static const _supportedTables = {
    'students',
    'attendance',
    'tests',
    'payments',
    'subjects',
    'missions',
    'mission_locations',
    'mission_participations',
    'mission_payments',
    'mission_payment_schedule',
    'ministry_entries',
    'users',
    'classes',
    'academic_sessions',
    'app_settings',
  };

  /// When we apply a remote INSERT we get a new local id; we store it here
  /// so that later UPDATE/DELETE for that recordId apply to the correct local row.
  final Map<String, int> _localIdByKey = {};

  String _key(String table, String recordId) => '$table:$recordId';

  /// Returns local primary key for (table, recordId), from in-run map or sync_record_mapping.
  Future<int?> _getLocalId(String table, String recordId) async {
    final key = _key(table, recordId);
    if (_localIdByKey.containsKey(key)) return _localIdByKey[key];
    final row = await (_db.select(_db.syncRecordMapping)
          ..where((t) =>
              t.entityTable.equals(table) & t.recordId.equals(recordId),))
        .getSingleOrNull();
    return row?.localId;
  }

  /// Resolve a remote FK id to a local id via mapping; falls back to the raw id
  /// when no mapping exists (same-device or already-aligned ids).
  Future<int?> _resolveFk(String table, dynamic remoteId) async {
    if (remoteId == null) return null;
    final asString = remoteId is int
        ? remoteId.toString()
        : (remoteId is num ? remoteId.toInt().toString() : remoteId.toString());
    final mapped = await _getLocalId(table, asString);
    if (mapped != null) return mapped;
    return int.tryParse(asString);
  }

  Future<int?> _resolveSessionId(String? sessionCode) async {
    if (sessionCode == null || sessionCode.trim().isEmpty) return null;
    try {
      final result = await _db.customSelect(
        'SELECT id FROM academic_sessions WHERE code = ? LIMIT 1',
        variables: [Variable.withString(sessionCode.trim())],
        readsFrom: const {},
      ).getSingleOrNull();
      return result?.data['id'] as int?;
    } catch (_) {
      return null;
    }
  }

  /// Resolve class by [className] in payload. Never uses remote numeric classId.
  Future<int?> _resolveClassIdFromPayload(Map<String, dynamic> payload) async {
    final name = payload['className'] as String?;
    if (name == null || name.trim().isEmpty) return null;
    final row = await (_db.select(_db.classes)
          ..where((t) => t.name.equals(name.trim())))
        .getSingleOrNull();
    return row?.id;
  }

  /// Persist mapping so future imports can resolve this recordId to localId.
  Future<void> _storeMapping(String table, String recordId, int localId) async {
    await _db.into(_db.syncRecordMapping).insertOnConflictUpdate(
          SyncRecordMappingCompanion.insert(
            entityTable: table,
            recordId: recordId,
            localId: localId,
          ),
        );
    _localIdByKey[_key(table, recordId)] = localId;
  }

  /// Check if table is critical for conflict resolution.
  bool _isCriticalTable(String table) =>
      table == 'payments' ||
      table == 'students' ||
      table == 'users' ||
      table == 'app_settings';

  /// Apply one change-set. Returns [ApplyResultApplied], [ApplyResultConflict], or [ApplyResultSkipped].
  Future<ApplyResult> tryApply(ChangeSetRecord record) async {
    Map<String, dynamic>? payload;
    try {
      final decoded = jsonDecode(record.payload);
      if (decoded is! Map<String, dynamic>) {
        return ApplyResultSkipped(
          reason: 'payload not an object',
          permanent: true,
        );
      }
      payload = decoded;
    } catch (_) {
      return ApplyResultSkipped(reason: 'corrupt payload', permanent: true);
    }

    if (!_supportedTables.contains(record.table)) {
      return ApplyResultSkipped(
        reason: 'unsupported table: ${record.table}',
        permanent: true,
      );
    }

    // Device-local settings must never be applied from remote.
    if (record.table == 'app_settings' &&
        AppSettingsRepository.deviceLocalKeys.contains(record.recordId)) {
      return ApplyResultSkipped(
        reason: 'device-local setting',
        permanent: true,
      );
    }
    if (record.table == 'app_settings') {
      final key = payload['key'] as String? ?? record.recordId;
      if (AppSettingsRepository.deviceLocalKeys.contains(key)) {
        return ApplyResultSkipped(
          reason: 'device-local setting',
          permanent: true,
        );
      }
    }

    // Conflict check for critical tables before applying
    if (_isCriticalTable(record.table)) {
      final conflict = await _checkCriticalConflict(record, payload);
      if (conflict != null) return conflict;
    }

    var applied = false;
    await _db.transaction(() async {
      switch (record.table) {
        case 'students':
          applied = await _applyStudents(record, payload!);
          break;
        case 'attendance':
          applied = await _applyAttendance(record, payload!);
          break;
        case 'tests':
          applied = await _applyTests(record, payload!);
          break;
        case 'payments':
          applied = await _applyPayments(record, payload!);
          break;
        case 'subjects':
          applied = await _applySubjects(record, payload!);
          break;
        case 'missions':
          applied = await _applyMissions(record, payload!);
          break;
        case 'mission_locations':
          applied = await _applyMissionLocations(record, payload!);
          break;
        case 'mission_participations':
          applied = await _applyMissionParticipations(record, payload!);
          break;
        case 'mission_payments':
          applied = await _applyMissionPayments(record, payload!);
          break;
        case 'mission_payment_schedule':
          applied = await _applyMissionPaymentSchedule(record, payload!);
          break;
        case 'ministry_entries':
          applied = await _applyMinistryEntries(record, payload!);
          break;
        case 'users':
          applied = await _applyUsers(record, payload!);
          break;
        case 'classes':
          applied = await _applyClasses(record, payload!);
          break;
        case 'academic_sessions':
          applied = await _applyAcademicSessions(record, payload!);
          break;
        case 'app_settings':
          applied = await _applyAppSettings(record, payload!);
          break;
      }

      if (applied) {
        await _db.into(_db.changeSets).insert(
              ChangeSetsCompanion.insert(
                id: record.id,
                table: record.table,
                recordId: record.recordId,
                operation: record.operation,
                payload: record.payload,
                timestamp: Value(record.timestamp),
                userId: record.userId,
                version: record.version,
                deviceId: record.deviceId,
              ),
            );
      }
    });
    if (!applied) {
      return ApplyResultSkipped(reason: 'apply produced no change');
    }
    return ApplyResultApplied();
  }

  /// Legacy entry point: apply without conflict handling (e.g. when resolving "use incoming").
  Future<void> apply(ChangeSetRecord record) async {
    final result = await tryApply(record);
    if (result is ApplyResultConflict) {
      throw StateError(
          'Conflict detected for ${record.table}:${record.recordId}',);
    }
  }

  /// Apply incoming payload only (for conflict resolution "Use incoming"). Does not insert into change_sets.
  Future<void> applyIncomingPayloadForConflict(
      String tableName, String recordId, String payloadJson,) async {
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>?;
    if (payload == null) return;

    if (tableName == 'app_settings') {
      final key = payload['key'] as String? ?? recordId;
      if (AppSettingsRepository.deviceLocalKeys.contains(key)) return;
      final value = payload['value'] as String?;
      if (value == null) {
        await (_db.delete(_db.appSettings)..where((s) => s.key.equals(key)))
            .go();
      } else {
        await _db.into(_db.appSettings).insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: key,
                value: Value(value),
              ),
            );
        if (key == AppSettingsRepository.keyCurrentAcademicSession) {
          await _applyCurrentSessionSideEffects(value);
        }
      }
      return;
    }

    final localId = await _getLocalId(tableName, recordId) ??
        (tableName == 'users'
            ? (await _findUserByUsername(payload['username'] as String?))?.id
            : null) ??
        int.tryParse(recordId);
    if (localId == null) return;
    if (tableName == 'students') {
      final classId = await _resolveClassIdFromPayload(payload);
      final sessionId =
          await _resolveSessionId(payload['academicSession'] as String?);
      await (_db.update(_db.students)..where((t) => t.id.equals(localId)))
          .write(
        StudentsCompanion(
          surname: _optValue<String>(payload['surname']),
          firstName: _optValue<String>(payload['firstName']),
          status: _optValue<String>(payload['status']),
          classId: classId != null
              ? Value(classId)
              : (payload.containsKey('className')
                  ? const Value(null)
                  : const Value.absent()),
          mode: _optValue<String>(payload['mode']),
          admissionYear: _optValue<String>(payload['admissionYear']),
          contactInfo: _optValue<String>(payload['contactInfo']),
          email: _optValue<String>(payload['email']),
          handbook: payload['handbook'] != null
              ? Value(payload['handbook'] as bool)
              : const Value.absent(),
          mediaRelease: payload['mediaRelease'] != null
              ? Value(payload['mediaRelease'] as bool)
              : const Value.absent(),
          accidentWaiver: payload['accidentWaiver'] != null
              ? Value(payload['accidentWaiver'] as bool)
              : const Value.absent(),
          academicSessionId: sessionId != null
              ? Value(sessionId)
              : (payload.containsKey('academicSession')
                  ? const Value(null)
                  : const Value.absent()),
          updatedAt: Value(DateTime.now()),
          version: payload['version'] != null
              ? Value(payload['version'] as int)
              : const Value.absent(),
        ),
      );
    } else if (tableName == 'payments') {
      double getDouble(String k) =>
          (payload[k] is num) ? (payload[k] as num).toDouble() : 0.0;
      final sessionId = await _resolveSessionId(payload['academicSession'] as String?);
      await (_db.update(_db.payments)..where((t) => t.id.equals(localId)))
          .write(
        PaymentsCompanion(
          jan: Value(getDouble('jan')),
          feb: Value(getDouble('feb')),
          mar: Value(getDouble('mar')),
          apr: Value(getDouble('apr')),
          may: Value(getDouble('may')),
          jun: Value(getDouble('jun')),
          jul: Value(getDouble('jul')),
          aug: Value(getDouble('aug')),
          sep: Value(getDouble('sep')),
          oct: Value(getDouble('oct')),
          nov: Value(getDouble('nov')),
          dec: Value(getDouble('dec')),
          lumpSum: Value(getDouble('lumpSum')),
          academicSessionId:
              sessionId != null ? Value(sessionId) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        ),
      );
    } else if (tableName == 'users') {
      final allowedClassId = await _resolveClassIdFromAllowedName(payload);
      await (_db.update(_db.users)..where((t) => t.id.equals(localId))).write(
        UsersCompanion(
          passwordHash: _optValue<String>(payload['passwordHash']),
          displayName: _optValue<String>(payload['displayName']),
          role: _optValue<String>(payload['role']),
          isActive: payload['isActive'] != null
              ? Value(payload['isActive'] as bool)
              : const Value.absent(),
          allowedClassId: payload.containsKey('allowedClassName')
              ? Value(allowedClassId)
              : const Value.absent(),
          allowedMode: _optValue<String>(payload['allowedMode']),
          updatedAt: payload['updatedAt'] is int
              ? Value(payload['updatedAt'] as int)
              : Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
    }
  }

  Future<ApplyResultConflict?> _checkCriticalConflict(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    if (record.table == 'students' &&
        (record.operation == 'UPDATE' ||
            record.operation == 'STATUS_CHANGE')) {
      final localId = await _getLocalId('students', record.recordId);
      if (localId == null) return null;
      final student = await (_db.select(_db.students)
            ..where((t) => t.id.equals(localId)))
          .getSingleOrNull();
      if (student == null) return null;
      final incomingVersion = payload['version'] as int? ?? 0;
      final baseVersion = payload['baseVersion'] as int?;
      final bool hasConflict;
      if (baseVersion != null) {
        hasConflict = student.version != baseVersion;
      } else if (incomingVersion > 0) {
        hasConflict = student.version != (incomingVersion - 1);
      } else {
        // Legacy payload missing baseVersion and no usable incoming version.
        return null;
      }
      if (hasConflict) {
        final localSnapshot = jsonEncode({
          'surname': student.surname,
          'firstName': student.firstName,
          'status': student.status,
          'classId': student.classId,
          'mode': student.mode,
          'version': student.version,
        });
        return ApplyResultConflict(
          changeSetId: record.id,
          tableName: record.table,
          recordId: record.recordId,
          incomingPayload: record.payload,
          localSnapshot: localSnapshot,
          sourceDeviceId: record.deviceId,
        );
      }
      return null;
    }
    if (record.table == 'payments' &&
        (record.operation == 'UPDATE' || record.operation == 'INSERT')) {
      final localId = await _getLocalId('payments', record.recordId);
      if (localId == null) return null;
      final payment = await (_db.select(_db.payments)
            ..where((t) => t.id.equals(localId)))
          .getSingleOrNull();
      if (payment == null) return null;
      if (payment.updatedAt.isAfter(record.timestamp)) {
        final localSnapshot = jsonEncode({
          'studentId': payment.studentId,
          'year': payment.year,
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
          'updatedAt': payment.updatedAt.toUtc().toIso8601String(),
        });
        return ApplyResultConflict(
          changeSetId: record.id,
          tableName: record.table,
          recordId: record.recordId,
          incomingPayload: record.payload,
          localSnapshot: localSnapshot,
          sourceDeviceId: record.deviceId,
        );
      }
      return null;
    }
    if (record.table == 'users' &&
        (record.operation == 'UPDATE' || record.operation == 'INSERT')) {
      final mappedId = await _getLocalId('users', record.recordId);
      User? local;
      if (mappedId != null) {
        local = await (_db.select(_db.users)
              ..where((t) => t.id.equals(mappedId)))
            .getSingleOrNull();
      }
      local ??= await _findUserByUsername(payload['username'] as String?);
      if (local == null) return null;
      final incomingUpdatedAt = payload['updatedAt'] is int
          ? payload['updatedAt'] as int
          : record.timestamp.millisecondsSinceEpoch;
      if (local.updatedAt > incomingUpdatedAt) {
        return ApplyResultConflict(
          changeSetId: record.id,
          tableName: record.table,
          recordId: record.recordId,
          incomingPayload: record.payload,
          localSnapshot: jsonEncode({
            'username': local.username,
            'passwordHash': local.passwordHash,
            'displayName': local.displayName,
            'role': local.role,
            'isActive': local.isActive,
            'updatedAt': local.updatedAt,
          }),
          sourceDeviceId: record.deviceId,
        );
      }
      return null;
    }
    if (record.table == 'app_settings' &&
        (record.operation == 'UPDATE' ||
            record.operation == 'INSERT' ||
            record.operation == 'DELETE')) {
      final key = payload['key'] as String? ?? record.recordId;
      if (AppSettingsRepository.deviceLocalKeys.contains(key)) return null;
      final local = await (_db.select(_db.appSettings)
            ..where((s) => s.key.equals(key)))
          .getSingleOrNull();
      if (local == null) return null;
      final incomingValue = payload['value'] as String?;
      if (record.operation == 'DELETE') {
        // Local still has a value while remote wants delete → conflict.
        return ApplyResultConflict(
          changeSetId: record.id,
          tableName: record.table,
          recordId: record.recordId,
          incomingPayload: record.payload,
          localSnapshot: jsonEncode({
            'key': local.key,
            'value': local.value,
          }),
          sourceDeviceId: record.deviceId,
        );
      }
      if (local.value != incomingValue) {
        // Prefer conflict when values diverge (admin chooses).
        return ApplyResultConflict(
          changeSetId: record.id,
          tableName: record.table,
          recordId: record.recordId,
          incomingPayload: record.payload,
          localSnapshot: jsonEncode({
            'key': local.key,
            'value': local.value,
          }),
          sourceDeviceId: record.deviceId,
        );
      }
      return null;
    }
    return null;
  }

  Future<bool> _applyStudents(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    final key = _key('students', record.recordId);
    switch (record.operation) {
      case 'INSERT':
        final classId = await _resolveClassIdFromPayload(payload);
        final sessionId =
            await _resolveSessionId(payload['academicSession'] as String?);
        final companion = StudentsCompanion.insert(
          surname: payload['surname'] as String? ?? '',
          firstName: payload['firstName'] as String? ?? '',
          classId: classId != null ? Value(classId) : const Value.absent(),
          mode: _optValue<String>(payload['mode']),
          admissionYear: _optValue<String>(payload['admissionYear']),
          contactInfo: _optValue<String>(payload['contactInfo']),
          email: _optValue<String>(payload['email']),
          handbook: Value(payload['handbook'] as bool? ?? false),
          mediaRelease: Value(payload['mediaRelease'] as bool? ?? false),
          accidentWaiver: Value(payload['accidentWaiver'] as bool? ?? false),
          status: Value(payload['status'] as String? ?? 'Active'),
          academicSessionId:
              sessionId != null ? Value(sessionId) : const Value.absent(),
        );
        final id = await _db.into(_db.students).insert(companion);
        await _storeMapping('students', record.recordId, id);
        return true;
      case 'UPDATE':
      case 'STATUS_CHANGE':
        final localId = await _getLocalId('students', record.recordId) ??
            int.tryParse(record.recordId);
        if (localId == null) return false;
        final classId = await _resolveClassIdFromPayload(payload);
        final sessionId =
            await _resolveSessionId(payload['academicSession'] as String?);
        final hasClassName = payload.containsKey('className');
        final hasSession = payload.containsKey('academicSession');
        await (_db.update(_db.students)..where((t) => t.id.equals(localId)))
            .write(
          StudentsCompanion(
            surname: _optValue<String>(payload['surname']),
            firstName: _optValue<String>(payload['firstName']),
            status: _optValue<String>(payload['status']),
            classId: classId != null
                ? Value(classId)
                : (hasClassName
                    ? const Value(null)
                    : const Value.absent()),
            mode: _optValue<String>(payload['mode']),
            admissionYear: _optValue<String>(payload['admissionYear']),
            contactInfo: _optValue<String>(payload['contactInfo']),
            email: _optValue<String>(payload['email']),
            handbook: payload['handbook'] != null
                ? Value(payload['handbook'] as bool)
                : const Value.absent(),
            mediaRelease: payload['mediaRelease'] != null
                ? Value(payload['mediaRelease'] as bool)
                : const Value.absent(),
            accidentWaiver: payload['accidentWaiver'] != null
                ? Value(payload['accidentWaiver'] as bool)
                : const Value.absent(),
            academicSessionId: sessionId != null
                ? Value(sessionId)
                : (hasSession
                    ? const Value(null)
                    : const Value.absent()),
            updatedAt: Value(DateTime.now()),
            version: payload['version'] != null
                ? Value(payload['version'] as int)
                : const Value.absent(),
          ),
        );
        _localIdByKey[key] = localId;
        return true;
      case 'DELETE':
        final localId = await _getLocalId('students', record.recordId) ??
            int.tryParse(record.recordId);
        if (localId == null) return false;
        await (_db.delete(_db.students)..where((t) => t.id.equals(localId)))
            .go();
        return true;
      default:
        return false;
    }
  }

  Future<bool> _applyAttendance(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    switch (record.operation) {
      case 'INSERT':
      case 'UPDATE':
        final dateStr = payload['date'] as String?;
        final studentId = await _resolveFk('students', payload['studentId']);
        if (dateStr == null || studentId == null) return false;
        final date = DateTime.parse(dateStr);
        final present = payload['present'] as bool? ?? false;
        final notes = payload['notes'] as String?;
        final sessionId =
            await _resolveSessionId(payload['academicSession'] as String?);
        final existing = await (_db.select(_db.attendance)
              ..where(
                  (t) => t.date.equals(date) & t.studentId.equals(studentId),))
            .getSingleOrNull();
        if (existing != null) {
          await (_db.update(_db.attendance)
                ..where((t) => t.id.equals(existing.id)))
              .write(
            AttendanceCompanion(
              present: Value(present ? 1 : 0),
              notes: notes != null && notes.isNotEmpty
                  ? Value(notes)
                  : const Value.absent(),
              academicSessionId:
                  sessionId != null ? Value(sessionId) : const Value.absent(),
            ),
          );
          await _storeMapping('attendance', record.recordId, existing.id);
        } else {
          final id = await _db.into(_db.attendance).insert(
                AttendanceCompanion.insert(
                  date: date,
                  studentId: studentId,
                  present: Value(present ? 1 : 0),
                  notes: notes != null && notes.isNotEmpty
                      ? Value(notes)
                      : const Value.absent(),
                  academicSessionId: sessionId != null
                      ? Value(sessionId)
                      : const Value.absent(),
                ),
              );
          await _storeMapping('attendance', record.recordId, id);
        }
        return true;
      case 'DELETE':
        final localId = await _getLocalId('attendance', record.recordId) ??
            int.tryParse(record.recordId);
        if (localId == null) return false;
        await (_db.delete(_db.attendance)..where((t) => t.id.equals(localId)))
            .go();
        return true;
      default:
        return false;
    }
  }

  Future<bool> _applyTests(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    final key = _key('tests', record.recordId);
    switch (record.operation) {
      case 'INSERT':
        final studentId = await _resolveFk('students', payload['studentId']);
        final score = payload['score'] as int? ?? 0;
        if (studentId == null) return false;
        final subjectId = payload['subjectId'] != null
            ? await _resolveFk('subjects', payload['subjectId'])
            : null;
        final sessionId =
            await _resolveSessionId(payload['academicSession'] as String?);
        final id = await _db.into(_db.tests).insert(
              TestsCompanion.insert(
                studentId: studentId,
                score: score,
                label: _optValue<String>(payload['label']),
                subjectId: subjectId != null
                    ? Value(subjectId)
                    : const Value.absent(),
                createdAt: Value(DateTime.now()),
                academicSession: _optValue<String>(payload['academicSession']),
                academicSessionId: sessionId != null
                    ? Value(sessionId)
                    : const Value.absent(),
              ),
            );
        await _storeMapping('tests', record.recordId, id);
        return true;
      case 'UPDATE':
        final localId = await _getLocalId('tests', record.recordId) ??
            int.tryParse(record.recordId);
        if (localId == null) return false;
        final subjectId = payload['subjectId'] != null
            ? await _resolveFk('subjects', payload['subjectId'])
            : null;
        await (_db.update(_db.tests)..where((t) => t.id.equals(localId))).write(
          TestsCompanion(
            score: payload['score'] != null
                ? Value(payload['score'] as int)
                : const Value.absent(),
            label: _optValue<String>(payload['label']),
            subjectId: subjectId != null
                ? Value(subjectId)
                : const Value.absent(),
            updatedAt: Value(DateTime.now()),
            academicSession: _optValue<String>(payload['academicSession']),
          ),
        );
        _localIdByKey[key] = localId;
        return true;
      case 'DELETE':
        if (record.recordId == 'all') {
          await _db.delete(_db.tests).go();
          return true;
        }
        final localId = await _getLocalId('tests', record.recordId) ??
            int.tryParse(record.recordId);
        if (localId == null) return false;
        await (_db.delete(_db.tests)..where((t) => t.id.equals(localId))).go();
        return true;
      default:
        return false;
    }
  }

  Future<bool> _applyPayments(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    final studentId = await _resolveFk('students', payload['studentId']);
    final year = payload['year'] as String?;
    if (studentId == null || year == null) return false;
    double getDouble(String k) =>
        (payload[k] is num) ? (payload[k] as num).toDouble() : 0.0;
    final sessionId =
        await _resolveSessionId(payload['academicSession'] as String?);
    switch (record.operation) {
      case 'INSERT':
      case 'UPDATE':
        final existing = await (_db.select(_db.payments)
              ..where(
                  (t) => t.studentId.equals(studentId) & t.year.equals(year),))
            .getSingleOrNull();
        if (existing != null) {
          await (_db.update(_db.payments)
                ..where((t) => t.id.equals(existing.id)))
              .write(
            PaymentsCompanion(
              jan: Value(getDouble('jan')),
              feb: Value(getDouble('feb')),
              mar: Value(getDouble('mar')),
              apr: Value(getDouble('apr')),
              may: Value(getDouble('may')),
              jun: Value(getDouble('jun')),
              jul: Value(getDouble('jul')),
              aug: Value(getDouble('aug')),
              sep: Value(getDouble('sep')),
              oct: Value(getDouble('oct')),
              nov: Value(getDouble('nov')),
              dec: Value(getDouble('dec')),
              lumpSum: Value(getDouble('lumpSum')),
              academicSessionId:
                  sessionId != null ? Value(sessionId) : const Value.absent(),
              updatedAt: Value(DateTime.now()),
            ),
          );
          await _storeMapping('payments', record.recordId, existing.id);
        } else {
          final now = DateTime.now();
          final id = await _db.into(_db.payments).insert(
                PaymentsCompanion.insert(
                  studentId: studentId,
                  year: year,
                  academicSessionId: sessionId != null
                      ? Value(sessionId)
                      : const Value.absent(),
                  jan: Value(getDouble('jan')),
                  feb: Value(getDouble('feb')),
                  mar: Value(getDouble('mar')),
                  apr: Value(getDouble('apr')),
                  may: Value(getDouble('may')),
                  jun: Value(getDouble('jun')),
                  jul: Value(getDouble('jul')),
                  aug: Value(getDouble('aug')),
                  sep: Value(getDouble('sep')),
                  oct: Value(getDouble('oct')),
                  nov: Value(getDouble('nov')),
                  dec: Value(getDouble('dec')),
                  lumpSum: Value(getDouble('lumpSum')),
                  createdAt: Value(now),
                  updatedAt: Value(now),
                ),
              );
          await _storeMapping('payments', record.recordId, id);
        }
        return true;
      case 'DELETE':
        final localId = await _getLocalId('payments', record.recordId) ??
            int.tryParse(record.recordId);
        if (localId == null) return false;
        await (_db.delete(_db.payments)..where((t) => t.id.equals(localId)))
            .go();
        return true;
      default:
        return false;
    }
  }

  Future<bool> _applySubjects(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    final key = _key('subjects', record.recordId);
    switch (record.operation) {
      case 'INSERT':
        final name = payload['name'] as String?;
        final classId = await _resolveClassIdFromPayload(payload);
        if (name == null || classId == null) return false;
        final sortOrder = await _resolveSubjectSortOrder(payload, classId);
        final id = await _db.into(_db.subjects).insert(
              SubjectsCompanion.insert(
                name: name,
                classId: classId,
                sortOrder: Value(sortOrder),
              ),
            );
        await _storeMapping('subjects', record.recordId, id);
        return true;
      case 'UPDATE':
        final localId = await _getLocalId('subjects', record.recordId) ??
            int.tryParse(record.recordId);
        if (localId == null) return false;
        final name = payload['name'] as String?;
        final sortOrder = _payloadInt(payload['sortOrder']);
        if (name != null || sortOrder != null) {
          await (_db.update(_db.subjects)..where((t) => t.id.equals(localId)))
              .write(
            SubjectsCompanion(
              name: name != null ? Value(name) : const Value.absent(),
              sortOrder:
                  sortOrder != null ? Value(sortOrder) : const Value.absent(),
            ),
          );
        }
        _localIdByKey[key] = localId;
        return true;
      case 'DELETE':
        final localId = await _getLocalId('subjects', record.recordId) ??
            int.tryParse(record.recordId);
        if (localId == null) return false;
        await (_db.delete(_db.subjects)..where((t) => t.id.equals(localId)))
            .go();
        return true;
      default:
        return false;
    }
  }

  Future<int> _resolveSubjectSortOrder(
    Map<String, dynamic> payload,
    int classId,
  ) async {
    final fromPayload = _payloadInt(payload['sortOrder']);
    if (fromPayload != null) return fromPayload;
    final result = await _db.customSelect(
      'SELECT MAX(sort_order) AS m FROM subjects WHERE class_id = ?',
      variables: [Variable.withInt(classId)],
      readsFrom: {_db.subjects},
    ).getSingleOrNull();
    final max = result?.readNullable<int>('m');
    return (max ?? -1) + 1;
  }

  int? _payloadInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  Future<bool> _applyMissions(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    final key = _key('missions', record.recordId);
    switch (record.operation) {
      case 'INSERT':
        final title = payload['title'] as String?;
        final location = payload['location'] as String?;
        final year = payload['year'] as String?;
        final mode = payload['mode'] as String?;
        if (title == null ||
            location == null ||
            year == null ||
            mode == null) {
          return false;
        }
        final startDate = payload['startDate'] != null
            ? DateTime.parse(payload['startDate'] as String)
            : DateTime.now();
        final endDate = payload['endDate'] != null
            ? DateTime.parse(payload['endDate'] as String)
            : DateTime.now();
        final slotsTotal = payload['slotsTotal'] as int? ?? 1;
        final sessionId =
            await _resolveSessionId(payload['academicSession'] as String?);
        final id = await _db.into(_db.missions).insert(
              MissionsCompanion.insert(
                title: title,
                location: location,
                startDate: startDate,
                endDate: endDate,
                slotsTotal: slotsTotal,
                description: _optValue<String>(payload['description']),
                isActive: Value(payload['isActive'] as bool? ?? true),
                year: year,
                mode: mode,
                amount: payload['amount'] != null
                    ? Value((payload['amount'] as num).toDouble())
                    : const Value.absent(),
                academicSessionId: sessionId != null
                    ? Value(sessionId)
                    : const Value.absent(),
              ),
            );
        await _storeMapping('missions', record.recordId, id);
        return true;
      case 'UPDATE':
        final localId = await _getLocalId('missions', record.recordId) ??
            int.tryParse(record.recordId);
        if (localId == null) return false;
        final comp = MissionsCompanion(
          title: _optValue<String>(payload['title']),
          location: _optValue<String>(payload['location']),
          startDate: payload['startDate'] != null
              ? Value(DateTime.parse(payload['startDate'] as String))
              : const Value.absent(),
          endDate: payload['endDate'] != null
              ? Value(DateTime.parse(payload['endDate'] as String))
              : const Value.absent(),
          slotsTotal: payload['slotsTotal'] != null
              ? Value(payload['slotsTotal'] as int)
              : const Value.absent(),
          description: _optValue<String>(payload['description']),
          isActive: payload['isActive'] != null
              ? Value(payload['isActive'] as bool)
              : const Value.absent(),
          year: _optValue<String>(payload['year']),
          mode: _optValue<String>(payload['mode']),
          amount: payload['amount'] != null
              ? Value((payload['amount'] as num).toDouble())
              : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        );
        await (_db.update(_db.missions)..where((t) => t.id.equals(localId)))
            .write(comp);
        _localIdByKey[key] = localId;
        return true;
      case 'DELETE':
        final localId = await _getLocalId('missions', record.recordId) ??
            int.tryParse(record.recordId);
        if (localId == null) return false;
        await (_db.delete(_db.missions)..where((t) => t.id.equals(localId)))
            .go();
        return true;
      default:
        return false;
    }
  }

  Future<bool> _applyMinistryEntries(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    final key = _key('ministry_entries', record.recordId);
    switch (record.operation) {
      case 'INSERT':
      case 'UPDATE':
        final studentId = await _resolveFk('students', payload['studentId']);
        final ministryType = payload['ministryType'] as String?;
        final dateStr = payload['date'] as String?;
        final hours = payload['hours'] is num
            ? (payload['hours'] as num).toDouble()
            : null;
        final year = payload['year'] as String?;
        final term = payload['term'] is int
            ? payload['term'] as int
            : (payload['term'] as num?)?.toInt();
        if (studentId == null ||
            ministryType == null ||
            dateStr == null ||
            hours == null ||
            year == null ||
            term == null) {
          return false;
        }
        final date = DateTime.parse(dateStr);
        final sessionId =
            await _resolveSessionId(payload['academicSession'] as String?);
        final classId = await _resolveClassIdFromPayload(payload);
        final mappedId = await _getLocalId('ministry_entries', record.recordId);
        final companion = MinistryEntriesCompanion(
          studentId: Value(studentId),
          year: Value(year),
          term: Value(term),
          classId: classId != null
              ? Value(classId)
              : (payload.containsKey('className')
                  ? const Value(null)
                  : const Value.absent()),
          studyMode: _optValue<String>(payload['studyMode']),
          ministryType: Value(ministryType),
          date: Value(date),
          hours: Value(hours),
          supervisor: _optValue<String>(payload['supervisor']),
          approved: payload['approved'] != null
              ? Value(payload['approved'] as bool)
              : const Value.absent(),
          notes: _optValue<String>(payload['notes']),
          updatedAt: Value(DateTime.now()),
          academicSessionId:
              sessionId != null ? Value(sessionId) : const Value.absent(),
        );
        if (mappedId != null) {
          await (_db.update(_db.ministryEntries)
                ..where((t) => t.id.equals(mappedId)))
              .write(companion);
          _localIdByKey[key] = mappedId;
          return true;
        } else if (record.operation == 'INSERT') {
          final id = await _db.into(_db.ministryEntries).insert(
                MinistryEntriesCompanion.insert(
                  studentId: studentId,
                  year: year,
                  term: term,
                  classId: classId != null
                      ? Value(classId)
                      : const Value.absent(),
                  studyMode: _optValue<String>(payload['studyMode']),
                  ministryType: ministryType,
                  date: date,
                  hours: hours,
                  supervisor: _optValue<String>(payload['supervisor']),
                  approved: Value(payload['approved'] as bool? ?? false),
                  notes: _optValue<String>(payload['notes']),
                  createdAt: Value(DateTime.now()),
                  academicSessionId: sessionId != null
                      ? Value(sessionId)
                      : const Value.absent(),
                ),
              );
          await _storeMapping('ministry_entries', record.recordId, id);
          return true;
        } else {
          // UPDATE without mapping: try natural match then insert
          final existing = await (_db.select(_db.ministryEntries)
                ..where((t) =>
                    t.studentId.equals(studentId) &
                    t.date.equals(date) &
                    t.ministryType.equals(ministryType),))
              .getSingleOrNull();
          if (existing != null) {
            await (_db.update(_db.ministryEntries)
                  ..where((t) => t.id.equals(existing.id)))
                .write(companion);
            await _storeMapping(
                'ministry_entries', record.recordId, existing.id,);
            return true;
          }
          return false;
        }
      case 'DELETE':
        final localId =
            await _getLocalId('ministry_entries', record.recordId) ??
                int.tryParse(record.recordId);
        if (localId == null) return false;
        await (_db.delete(_db.ministryEntries)
              ..where((t) => t.id.equals(localId)))
            .go();
        return true;
      default:
        return false;
    }
  }

  Future<bool> _applyMissionLocations(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    final key = _key('mission_locations', record.recordId);
    switch (record.operation) {
      case 'INSERT':
        final name = payload['name'] as String?;
        if (name == null || name.trim().isEmpty) return false;
        final id = await _db.into(_db.missionLocations).insert(
              MissionLocationsCompanion.insert(
                name: name.trim(),
                description: _optValue<String>(payload['description']),
                isActive: Value(payload['isActive'] as bool? ?? true),
              ),
            );
        await _storeMapping('mission_locations', record.recordId, id);
        return true;
      case 'UPDATE':
        final localId =
            await _getLocalId('mission_locations', record.recordId) ??
                int.tryParse(record.recordId);
        if (localId == null) return false;
        await (_db.update(_db.missionLocations)
              ..where((t) => t.id.equals(localId)))
            .write(
          MissionLocationsCompanion(
            name: _optValue<String>(payload['name']),
            description: _optValue<String>(payload['description']),
            isActive: payload['isActive'] != null
                ? Value(payload['isActive'] as bool)
                : const Value.absent(),
          ),
        );
        _localIdByKey[key] = localId;
        return true;
      case 'DELETE':
        final localId =
            await _getLocalId('mission_locations', record.recordId) ??
                int.tryParse(record.recordId);
        if (localId == null) return false;
        await (_db.delete(_db.missionLocations)
              ..where((t) => t.id.equals(localId)))
            .go();
        return true;
      default:
        return false;
    }
  }

  Future<bool> _applyMissionParticipations(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    final key = _key('mission_participations', record.recordId);
    switch (record.operation) {
      case 'INSERT':
      case 'UPDATE':
        final missionId = await _resolveFk('missions', payload['missionId']);
        final studentId = await _resolveFk('students', payload['studentId']);
        final role = payload['role'] as String? ?? 'Participant';
        final amount = payload['amount'] is num
            ? (payload['amount'] as num).toDouble()
            : 0.0;
        if (missionId == null || studentId == null) return false;

        final mappedId =
            await _getLocalId('mission_participations', record.recordId);
        if (mappedId != null) {
          await (_db.update(_db.missionParticipations)
                ..where((t) => t.id.equals(mappedId)))
              .write(
            MissionParticipationsCompanion(
              missionId: Value(missionId),
              studentId: Value(studentId),
              role: Value(role),
              amount: Value(amount),
            ),
          );
          _localIdByKey[key] = mappedId;
          return true;
        }

        final existing = await (_db.select(_db.missionParticipations)
              ..where((t) =>
                  t.missionId.equals(missionId) &
                  t.studentId.equals(studentId),))
            .getSingleOrNull();
        if (existing != null) {
          await (_db.update(_db.missionParticipations)
                ..where((t) => t.id.equals(existing.id)))
              .write(
            MissionParticipationsCompanion(
              role: Value(role),
              amount: Value(amount),
            ),
          );
          await _storeMapping(
              'mission_participations', record.recordId, existing.id,);
          return true;
        } else if (record.operation == 'INSERT') {
          final id = await _db.into(_db.missionParticipations).insert(
                MissionParticipationsCompanion.insert(
                  missionId: missionId,
                  studentId: studentId,
                  role: role,
                  amount: Value(amount),
                ),
              );
          await _storeMapping('mission_participations', record.recordId, id);
          return true;
        }
        return false;
      case 'DELETE':
        final localId =
            await _getLocalId('mission_participations', record.recordId) ??
                int.tryParse(record.recordId);
        if (localId == null) return false;
        await (_db.delete(_db.missionParticipations)
              ..where((t) => t.id.equals(localId)))
            .go();
        return true;
      default:
        return false;
    }
  }

  Future<bool> _applyMissionPayments(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    switch (record.operation) {
      case 'INSERT':
        final participationId = await _resolveFk(
            'mission_participations', payload['missionParticipationId'],);
        final dateStr = payload['paymentDate'] as String?;
        final amount = payload['amount'] is num
            ? (payload['amount'] as num).toDouble()
            : null;
        if (participationId == null || dateStr == null || amount == null) {
          return false;
        }
        final sessionId =
            await _resolveSessionId(payload['academicSession'] as String?);
        final id = await _db.into(_db.missionPayments).insert(
              MissionPaymentsCompanion.insert(
                missionParticipationId: participationId,
                paymentDate: DateTime.parse(dateStr),
                amount: amount,
                academicSessionId: sessionId != null
                    ? Value(sessionId)
                    : const Value.absent(),
              ),
            );
        await _storeMapping('mission_payments', record.recordId, id);
        return true;
      case 'DELETE':
        final localId =
            await _getLocalId('mission_payments', record.recordId) ??
                int.tryParse(record.recordId);
        if (localId == null) return false;
        await (_db.delete(_db.missionPayments)
              ..where((t) => t.id.equals(localId)))
            .go();
        return true;
      default:
        return false;
    }
  }

  Future<bool> _applyMissionPaymentSchedule(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    final studentId = await _resolveFk('students', payload['studentId']);
    final year = payload['year'] as String?;
    if (studentId == null || year == null) return false;
    double getDouble(String k) =>
        (payload[k] is num) ? (payload[k] as num).toDouble() : 0.0;
    final sessionId =
        await _resolveSessionId(payload['academicSession'] as String?);
    switch (record.operation) {
      case 'INSERT':
      case 'UPDATE':
        final existing = await (_db.select(_db.missionPaymentSchedule)
              ..where(
                  (t) => t.studentId.equals(studentId) & t.year.equals(year),))
            .getSingleOrNull();
        final companion = MissionPaymentScheduleCompanion(
          tripSelected: _optValue<String>(payload['tripSelected']),
          date: payload['date'] != null
              ? Value((payload['date'] as num).toInt())
              : const Value.absent(),
          amount: Value(getDouble('amount')),
          mar: Value(getDouble('mar')),
          apr: Value(getDouble('apr')),
          may: Value(getDouble('may')),
          jun: Value(getDouble('jun')),
          jul: Value(getDouble('jul')),
          aug: Value(getDouble('aug')),
          sep: Value(getDouble('sep')),
          oct: Value(getDouble('oct')),
          comment: _optValue<String>(payload['comment']),
          academicSessionId:
              sessionId != null ? Value(sessionId) : const Value.absent(),
        );
        if (existing != null) {
          await (_db.update(_db.missionPaymentSchedule)
                ..where((t) => t.id.equals(existing.id)))
              .write(companion);
          await _storeMapping(
              'mission_payment_schedule', record.recordId, existing.id,);
        } else {
          final id = await _db.into(_db.missionPaymentSchedule).insert(
                MissionPaymentScheduleCompanion.insert(
                  studentId: studentId,
                  year: year,
                  academicSessionId: sessionId != null
                      ? Value(sessionId)
                      : const Value.absent(),
                  tripSelected: _optValue<String>(payload['tripSelected']),
                  date: payload['date'] != null
                      ? Value((payload['date'] as num).toInt())
                      : const Value.absent(),
                  amount: Value(getDouble('amount')),
                  mar: Value(getDouble('mar')),
                  apr: Value(getDouble('apr')),
                  may: Value(getDouble('may')),
                  jun: Value(getDouble('jun')),
                  jul: Value(getDouble('jul')),
                  aug: Value(getDouble('aug')),
                  sep: Value(getDouble('sep')),
                  oct: Value(getDouble('oct')),
                  comment: _optValue<String>(payload['comment']),
                ),
              );
          await _storeMapping('mission_payment_schedule', record.recordId, id);
        }
        return true;
      case 'DELETE':
        final localId =
            await _getLocalId('mission_payment_schedule', record.recordId) ??
                int.tryParse(record.recordId);
        if (localId == null) return false;
        await (_db.delete(_db.missionPaymentSchedule)
              ..where((t) => t.id.equals(localId)))
            .go();
        return true;
      default:
        return false;
    }
  }

  Future<User?> _findUserByUsername(String? username) async {
    if (username == null || username.trim().isEmpty) return null;
    return (_db.select(_db.users)
          ..where((t) => t.username.equals(username.trim())))
        .getSingleOrNull();
  }

  Future<int?> _resolveClassIdFromAllowedName(
      Map<String, dynamic> payload,) async {
    final name = payload['allowedClassName'] as String?;
    if (name == null || name.trim().isEmpty) return null;
    final row = await (_db.select(_db.classes)
          ..where((t) => t.name.equals(name.trim())))
        .getSingleOrNull();
    return row?.id;
  }

  Future<int?> _resolveUserIdByUsername(String? username) async {
    final user = await _findUserByUsername(username);
    return user?.id;
  }

  Future<void> _applyCurrentSessionSideEffects(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    await _db.customStatement(
      '''
      INSERT OR IGNORE INTO academic_sessions (code, is_active)
      VALUES (?, 0)
      ''',
      [trimmed],
    );
    await _db.customStatement(
      'UPDATE academic_sessions SET is_active = 0 WHERE code <> ?',
      [trimmed],
    );
    await _db.customStatement(
      'UPDATE academic_sessions SET is_active = 1 WHERE code = ?',
      [trimmed],
    );
  }

  Future<bool> _applyUsers(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    final username = payload['username'] as String?;
    if (username == null || username.trim().isEmpty) return false;
    switch (record.operation) {
      case 'INSERT':
      case 'UPDATE':
        final passwordHash = payload['passwordHash'] as String?;
        if (passwordHash == null || passwordHash.isEmpty) return false;
        final allowedClassId = await _resolveClassIdFromAllowedName(payload);
        // If facilitator scope references a class that is not present yet, retry later.
        if (payload.containsKey('allowedClassName') &&
            (payload['allowedClassName'] as String?)?.trim().isNotEmpty ==
                true &&
            allowedClassId == null) {
          return false;
        }
        final mappedId = await _getLocalId('users', record.recordId);
        final existing = mappedId != null
            ? await (_db.select(_db.users)
                  ..where((t) => t.id.equals(mappedId)))
                .getSingleOrNull()
            : await _findUserByUsername(username);
        final updatedAt = payload['updatedAt'] is int
            ? payload['updatedAt'] as int
            : DateTime.now().millisecondsSinceEpoch;
        final createdAt = payload['createdAt'] is int
            ? payload['createdAt'] as int
            : updatedAt;
        if (existing != null) {
          await (_db.update(_db.users)..where((t) => t.id.equals(existing.id)))
              .write(
            UsersCompanion(
              username: Value(username.trim()),
              passwordHash: Value(passwordHash),
              displayName: _optValue<String>(payload['displayName']),
              role: Value(payload['role'] as String? ?? existing.role),
              isActive: payload['isActive'] != null
                  ? Value(payload['isActive'] as bool)
                  : const Value.absent(),
              allowedClassId: payload.containsKey('allowedClassName')
                  ? Value(allowedClassId)
                  : const Value.absent(),
              allowedMode: payload.containsKey('allowedMode')
                  ? Value(payload['allowedMode'] as String?)
                  : const Value.absent(),
              updatedAt: Value(updatedAt),
            ),
          );
          await _storeMapping('users', record.recordId, existing.id);
          return true;
        }
        if (record.operation == 'UPDATE') {
          // No local row yet — treat as insert.
        }
        final id = await _db.into(_db.users).insert(
              UsersCompanion.insert(
                username: username.trim(),
                passwordHash: passwordHash,
                displayName: Value(payload['displayName'] as String?),
                role: payload['role'] as String? ?? 'facilitator',
                allowedClassId: Value(allowedClassId),
                allowedMode: Value(payload['allowedMode'] as String?),
                isActive: Value(payload['isActive'] as bool? ?? true),
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
            );
        await _storeMapping('users', record.recordId, id);
        return true;
      case 'DELETE':
        final localId = await _getLocalId('users', record.recordId) ??
            (await _findUserByUsername(username))?.id ??
            int.tryParse(record.recordId);
        if (localId == null) return false;
        await (_db.update(_db.classes)
              ..where((c) => c.facilitatorUserId.equals(localId)))
            .write(const ClassesCompanion(facilitatorUserId: Value(null)));
        await (_db.delete(_db.users)..where((t) => t.id.equals(localId))).go();
        return true;
      default:
        return false;
    }
  }

  Future<bool> _applyClasses(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    final name = payload['name'] as String?;
    if (name == null || name.trim().isEmpty) return false;
    switch (record.operation) {
      case 'INSERT':
      case 'UPDATE':
        final facilitatorUsername = payload['facilitatorUsername'] as String?;
        int? facilitatorUserId;
        if (facilitatorUsername != null &&
            facilitatorUsername.trim().isNotEmpty) {
          facilitatorUserId =
              await _resolveUserIdByUsername(facilitatorUsername);
          if (facilitatorUserId == null) return false; // retry when user arrives
        }
        final mappedClassId = await _getLocalId('classes', record.recordId);
        final existing = mappedClassId != null
            ? await (_db.select(_db.classes)
                  ..where((t) => t.id.equals(mappedClassId)))
                .getSingleOrNull()
            : await (_db.select(_db.classes)
                  ..where((t) => t.name.equals(name.trim())))
                .getSingleOrNull();
        final sortOrder = payload['sortOrder'] is int
            ? payload['sortOrder'] as int
            : (payload['sortOrder'] as num?)?.toInt() ?? 0;
        if (existing != null) {
          await (_db.update(_db.classes)
                ..where((t) => t.id.equals(existing.id)))
              .write(
            ClassesCompanion(
              name: Value(name.trim()),
              sortOrder: Value(sortOrder),
              facilitatorUserId: payload.containsKey('facilitatorUsername')
                  ? Value(facilitatorUserId)
                  : const Value.absent(),
              updatedAt: Value(DateTime.now()),
            ),
          );
          await _storeMapping('classes', record.recordId, existing.id);
          return true;
        }
        final id = await _db.into(_db.classes).insert(
              ClassesCompanion.insert(
                name: name.trim(),
                sortOrder: Value(sortOrder),
                facilitatorUserId: Value(facilitatorUserId),
              ),
            );
        await _storeMapping('classes', record.recordId, id);
        return true;
      case 'DELETE':
        // Classes are not deleted in-app; ignore remote DELETE.
        return false;
      default:
        return false;
    }
  }

  Future<bool> _applyAcademicSessions(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    final code = payload['code'] as String?;
    if (code == null || code.trim().isEmpty) return false;
    switch (record.operation) {
      case 'INSERT':
      case 'UPDATE':
        final mappedSessionId =
            await _getLocalId('academic_sessions', record.recordId);
        final existing = mappedSessionId != null
            ? await (_db.select(_db.academicSessions)
                  ..where((t) => t.id.equals(mappedSessionId)))
                .getSingleOrNull()
            : await (_db.select(_db.academicSessions)
                  ..where((t) => t.code.equals(code.trim())))
                .getSingleOrNull();
        final startDate = payload['startDate'] is int
            ? payload['startDate'] as int
            : (payload['startDate'] as num?)?.toInt();
        final endDate = payload['endDate'] is int
            ? payload['endDate'] as int
            : (payload['endDate'] as num?)?.toInt();
        final isActive = payload['isActive'] as bool? ?? false;
        if (existing != null) {
          await (_db.update(_db.academicSessions)
                ..where((t) => t.id.equals(existing.id)))
              .write(
            AcademicSessionsCompanion(
              code: Value(code.trim()),
              startDate: startDate != null
                  ? Value(startDate)
                  : const Value.absent(),
              endDate:
                  endDate != null ? Value(endDate) : const Value.absent(),
              isActive: Value(isActive),
              displayName: _optValue<String>(payload['displayName']),
            ),
          );
          if (isActive) {
            await _db.customStatement(
              'UPDATE academic_sessions SET is_active = 0 WHERE code <> ?',
              [code.trim()],
            );
          }
          await _storeMapping(
              'academic_sessions', record.recordId, existing.id,);
          return true;
        }
        final id = await _db.into(_db.academicSessions).insert(
              AcademicSessionsCompanion.insert(
                code: code.trim(),
                startDate: Value(startDate),
                endDate: Value(endDate),
                isActive: Value(isActive),
                displayName: Value(payload['displayName'] as String?),
              ),
            );
        if (isActive) {
          await _db.customStatement(
            'UPDATE academic_sessions SET is_active = 0 WHERE code <> ?',
            [code.trim()],
          );
        }
        await _storeMapping('academic_sessions', record.recordId, id);
        return true;
      case 'DELETE':
        return false;
      default:
        return false;
    }
  }

  Future<bool> _applyAppSettings(
      ChangeSetRecord record, Map<String, dynamic> payload,) async {
    final key = payload['key'] as String? ?? record.recordId;
    if (key.trim().isEmpty) return false;
    if (AppSettingsRepository.deviceLocalKeys.contains(key)) return false;
    if (!AppSettingsRepository.syncableKeys.contains(key)) {
      // Unknown keys: apply as upsert for forward compatibility except device-local.
    }
    switch (record.operation) {
      case 'INSERT':
      case 'UPDATE':
        final value = payload['value'] as String?;
        if (value == null) return false;
        await _db.into(_db.appSettings).insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: key,
                value: Value(value),
              ),
            );
        if (key == AppSettingsRepository.keyCurrentAcademicSession) {
          await _applyCurrentSessionSideEffects(value);
        }
        return true;
      case 'DELETE':
        await (_db.delete(_db.appSettings)..where((s) => s.key.equals(key)))
            .go();
        return true;
      default:
        return false;
    }
  }

  Value<T> _optValue<T>(dynamic v) {
    if (v == null) return Value.absent();
    return Value(v as T);
  }

  /// After "keep local", emit a change-set so peers converge on this device's values.
  Future<bool> writeKeepLocalHealChangeSet({
    required String tableName,
    required String recordId,
    required String userId,
    required String deviceId,
    String? localSnapshot,
    void Function()? onWritten,
  }) async {
    late Map<String, dynamic> payload;
    String operation = 'UPDATE';
    String outRecordId = recordId;

    if (tableName == 'students') {
      final localId =
          await _getLocalId('students', recordId) ?? int.tryParse(recordId);
      if (localId == null) return false;
      final s = await (_db.select(_db.students)
            ..where((t) => t.id.equals(localId)))
          .getSingleOrNull();
      if (s == null) return false;
      String? className;
      if (s.classId != null) {
        final c = await (_db.select(_db.classes)
              ..where((t) => t.id.equals(s.classId!)))
            .getSingleOrNull();
        className = c?.name;
      }
      payload = {
        'surname': s.surname,
        'firstName': s.firstName,
        'status': s.status,
        if (className != null) 'className': className,
        'mode': s.mode,
        'admissionYear': s.admissionYear,
        'contactInfo': s.contactInfo,
        'email': s.email,
        'handbook': s.handbook,
        'mediaRelease': s.mediaRelease,
        'accidentWaiver': s.accidentWaiver,
        'baseVersion': s.version,
        'version': s.version + 1,
      };
      await (_db.update(_db.students)..where((t) => t.id.equals(localId)))
          .write(StudentsCompanion(
        version: Value(s.version + 1),
        updatedAt: Value(DateTime.now()),
      ),);
      outRecordId = localId.toString();
    } else if (tableName == 'payments') {
      final localId =
          await _getLocalId('payments', recordId) ?? int.tryParse(recordId);
      if (localId == null) return false;
      final p = await (_db.select(_db.payments)
            ..where((t) => t.id.equals(localId)))
          .getSingleOrNull();
      if (p == null) return false;
      payload = {
        'studentId': p.studentId,
        'year': p.year,
        'jan': p.jan,
        'feb': p.feb,
        'mar': p.mar,
        'apr': p.apr,
        'may': p.may,
        'jun': p.jun,
        'jul': p.jul,
        'aug': p.aug,
        'sep': p.sep,
        'oct': p.oct,
        'nov': p.nov,
        'dec': p.dec,
        'lumpSum': p.lumpSum,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      };
      outRecordId = localId.toString();
    } else if (tableName == 'users') {
      final mappedId = await _getLocalId('users', recordId);
      final localId = mappedId ?? int.tryParse(recordId);
      User? u;
      if (localId != null) {
        u = await (_db.select(_db.users)..where((t) => t.id.equals(localId)))
            .getSingleOrNull();
      }
      if (u == null && localSnapshot != null) {
        try {
          final snap = jsonDecode(localSnapshot) as Map<String, dynamic>?;
          u = await _findUserByUsername(snap?['username'] as String?);
        } catch (_) {}
      }
      if (u == null) return false;
      String? allowedClassName;
      if (u.allowedClassId != null) {
        final c = await (_db.select(_db.classes)
              ..where((t) => t.id.equals(u!.allowedClassId!)))
            .getSingleOrNull();
        allowedClassName = c?.name;
      }
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      await (_db.update(_db.users)..where((t) => t.id.equals(u!.id))).write(
        UsersCompanion(updatedAt: Value(nowMs)),
      );
      payload = {
        'username': u.username,
        'passwordHash': u.passwordHash,
        'displayName': u.displayName,
        'role': u.role,
        'isActive': u.isActive,
        if (allowedClassName != null) 'allowedClassName': allowedClassName,
        if (u.allowedMode != null) 'allowedMode': u.allowedMode,
        'updatedAt': nowMs,
        'createdAt': u.createdAt,
      };
      outRecordId = u.id.toString();
    } else if (tableName == 'app_settings') {
      final key = recordId;
      final row = await (_db.select(_db.appSettings)
            ..where((s) => s.key.equals(key)))
          .getSingleOrNull();
      if (row == null) {
        operation = 'DELETE';
        payload = {
          'key': key,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        };
      } else {
        payload = {
          'key': row.key,
          'value': row.value,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        };
      }
      outRecordId = key;
    } else {
      return false;
    }

    await _db.into(_db.changeSets).insert(
          ChangeSetsCompanion.insert(
            id: _uuid.v4(),
            table: tableName,
            recordId: outRecordId,
            operation: operation,
            payload: jsonEncode(payload),
            userId: userId,
            version: 1,
            deviceId: deviceId,
          ),
        );
    onWritten?.call();
    return true;
  }
}
