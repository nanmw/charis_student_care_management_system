import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/services/change_set_sync_service.dart';

/// Applies a single change-set to the local DB and records it in change_sets.
/// Maintains a mapping of (table:remoteRecordId) -> localId for INSERT/UPDATE/DELETE.
/// For critical tables (payments, students status) detects conflicts and returns [ApplyResultConflict].
class ChangeSetApplier {
  ChangeSetApplier(this._db);

  final AppDatabase _db;

  /// When we apply a remote INSERT we get a new local id; we store it here
  /// so that later UPDATE/DELETE for that recordId apply to the correct local row.
  final Map<String, int> _localIdByKey = {};

  String _key(String table, String recordId) => '$table:$recordId';

  /// Returns local primary key for (table, recordId), from in-run map or sync_record_mapping.
  Future<int?> _getLocalId(String table, String recordId) async {
    final key = _key(table, recordId);
    if (_localIdByKey.containsKey(key)) return _localIdByKey[key];
    final row = await (_db.select(_db.syncRecordMapping)
          ..where((t) => t.entityTable.equals(table) & t.recordId.equals(recordId)))
        .getSingleOrNull();
    return row?.localId;
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
  }

  /// Check if table is critical for conflict resolution (payments; students for status/update).
  bool _isCriticalTable(String table) => table == 'payments' || table == 'students';

  /// Apply one change-set. Returns [ApplyResultApplied] or [ApplyResultConflict] for critical clashes.
  Future<ApplyResult> tryApply(ChangeSetRecord record) async {
    final payload = jsonDecode(record.payload) as Map<String, dynamic>?;
    if (payload == null) return ApplyResultApplied();

    // Conflict check for critical tables before applying
    if (_isCriticalTable(record.table)) {
      final conflict = await _checkCriticalConflict(record, payload);
      if (conflict != null) return conflict;
    }

    await _db.transaction(() async {
      switch (record.table) {
        case 'students':
          await _applyStudents(record, payload);
          break;
        case 'attendance':
          await _applyAttendance(record, payload);
          break;
        case 'tests':
          await _applyTests(record, payload);
          break;
        case 'payments':
          await _applyPayments(record, payload);
          break;
        case 'subjects':
          await _applySubjects(record, payload);
          break;
        case 'missions':
          await _applyMissions(record, payload);
          break;
        default:
          break;
      }

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
    });
    return ApplyResultApplied();
  }

  /// Legacy entry point: apply without conflict handling (e.g. when resolving "use incoming").
  Future<void> apply(ChangeSetRecord record) async {
    final result = await tryApply(record);
    if (result is ApplyResultConflict) {
      throw StateError('Conflict detected for ${record.table}:${record.recordId}');
    }
  }

  /// Apply incoming payload only (for conflict resolution "Use incoming"). Does not insert into change_sets.
  Future<void> applyIncomingPayloadForConflict(String tableName, String recordId, String payloadJson) async {
    final payload = jsonDecode(payloadJson) as Map<String, dynamic>?;
    if (payload == null) return;
    final localId = await _getLocalId(tableName, recordId);
    if (localId == null) return;
    if (tableName == 'students') {
      await (_db.update(_db.students)..where((t) => t.id.equals(localId))).write(
            StudentsCompanion(
              surname: _optValue<String>(payload['surname']),
              firstName: _optValue<String>(payload['firstName']),
              status: _optValue<String>(payload['status']),
              classId: _optValue<int>(payload['classId']),
              mode: _optValue<String>(payload['mode']),
              admissionYear: _optValue<String>(payload['admissionYear']),
              contactInfo: _optValue<String>(payload['contactInfo']),
              email: _optValue<String>(payload['email']),
              handbook: payload['handbook'] != null ? Value(payload['handbook'] as bool) : const Value.absent(),
              mediaRelease: payload['mediaRelease'] != null ? Value(payload['mediaRelease'] as bool) : const Value.absent(),
              accidentWaiver: payload['accidentWaiver'] != null ? Value(payload['accidentWaiver'] as bool) : const Value.absent(),
              updatedAt: Value(DateTime.now()),
              version: payload['version'] != null ? Value(payload['version'] as int) : const Value.absent(),
            ),
          );
    } else if (tableName == 'payments') {
      double getDouble(String k) => (payload[k] is num) ? (payload[k] as num).toDouble() : 0.0;
      await (_db.update(_db.payments)..where((t) => t.id.equals(localId))).write(
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
              updatedAt: Value(DateTime.now()),
            ),
          );
    }
  }

  Future<ApplyResultConflict?> _checkCriticalConflict(ChangeSetRecord record, Map<String, dynamic> payload) async {
    if (record.table == 'students' && (record.operation == 'UPDATE' || record.operation == 'STATUS_CHANGE')) {
      final localId = await _getLocalId('students', record.recordId);
      if (localId == null) return null;
      final student = await (_db.select(_db.students)..where((t) => t.id.equals(localId))).getSingleOrNull();
      if (student == null) return null;
      final incomingVersion = payload['version'] as int? ?? 0;
      if (student.version != incomingVersion) {
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
    if (record.table == 'payments' && (record.operation == 'UPDATE' || record.operation == 'INSERT')) {
      final localId = await _getLocalId('payments', record.recordId);
      if (localId == null) return null;
      final payment = await (_db.select(_db.payments)..where((t) => t.id.equals(localId))).getSingleOrNull();
      if (payment == null) return null;
      // Conflict if our copy was updated after the incoming change-set timestamp
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
    return null;
  }

  Future<void> _applyStudents(ChangeSetRecord record, Map<String, dynamic> payload) async {
    final key = _key('students', record.recordId);
    switch (record.operation) {
      case 'INSERT':
        final companion = StudentsCompanion.insert(
          surname: payload['surname'] as String? ?? '',
          firstName: payload['firstName'] as String? ?? '',
          classId: _optValue<int>(payload['classId']),
          mode: _optValue<String>(payload['mode']),
          admissionYear: _optValue<String>(payload['admissionYear']),
          contactInfo: _optValue<String>(payload['contactInfo']),
          email: _optValue<String>(payload['email']),
          handbook: Value(payload['handbook'] as bool? ?? false),
          mediaRelease: Value(payload['mediaRelease'] as bool? ?? false),
          accidentWaiver: Value(payload['accidentWaiver'] as bool? ?? false),
          status: Value(payload['status'] as String? ?? 'Active'),
        );
        final id = await _db.into(_db.students).insert(companion);
        _localIdByKey[key] = id;
        await _storeMapping('students', record.recordId, id);
        break;
      case 'UPDATE':
      case 'STATUS_CHANGE':
        final localId = _localIdByKey[key] ?? await _getLocalId('students', record.recordId) ?? int.tryParse(record.recordId);
        if (localId == null) return;
        await (_db.update(_db.students)..where((t) => t.id.equals(localId))).write(
          StudentsCompanion(
            surname: _optValue<String>(payload['surname']),
            firstName: _optValue<String>(payload['firstName']),
            status: _optValue<String>(payload['status']),
            classId: _optValue<int>(payload['classId']),
            mode: _optValue<String>(payload['mode']),
            admissionYear: _optValue<String>(payload['admissionYear']),
            contactInfo: _optValue<String>(payload['contactInfo']),
            email: _optValue<String>(payload['email']),
            handbook: payload['handbook'] != null ? Value(payload['handbook'] as bool) : const Value.absent(),
            mediaRelease: payload['mediaRelease'] != null ? Value(payload['mediaRelease'] as bool) : const Value.absent(),
            accidentWaiver: payload['accidentWaiver'] != null ? Value(payload['accidentWaiver'] as bool) : const Value.absent(),
            updatedAt: Value(DateTime.now()),
            version: payload['version'] != null ? Value(payload['version'] as int) : const Value.absent(),
          ),
        );
        break;
      case 'DELETE':
        final localId = _localIdByKey[key] ?? await _getLocalId('students', record.recordId) ?? int.tryParse(record.recordId);
        if (localId == null) return;
        await (_db.delete(_db.students)..where((t) => t.id.equals(localId))).go();
        break;
    }
  }

  Future<void> _applyAttendance(ChangeSetRecord record, Map<String, dynamic> payload) async {
    final key = _key('attendance', record.recordId);
    switch (record.operation) {
      case 'INSERT':
      case 'UPDATE':
        final dateStr = payload['date'] as String?;
        final studentId = payload['studentId'] as int?;
        if (dateStr == null || studentId == null) return;
        final date = DateTime.parse(dateStr);
        final present = payload['present'] as bool? ?? false;
        final notes = payload['present'] == null ? null : (payload['notes'] as String?);
        final existing = await (_db.select(_db.attendance)
              ..where((t) => t.date.equals(date) & t.studentId.equals(studentId)))
            .getSingleOrNull();
        if (existing != null) {
          await (_db.update(_db.attendance)..where((t) => t.id.equals(existing.id))).write(
            AttendanceCompanion(
              present: Value(present ? 1 : 0),
              notes: notes != null && notes.isNotEmpty ? Value(notes) : const Value.absent(),
            ),
          );
          _localIdByKey[key] = existing.id;
        } else {
          final id = await _db.into(_db.attendance).insert(
            AttendanceCompanion.insert(
              date: date,
              studentId: studentId,
              present: Value(present ? 1 : 0),
              notes: notes != null && notes.isNotEmpty ? Value(notes) : const Value.absent(),
            ),
          );
          _localIdByKey[key] = id;
        }
        break;
      case 'DELETE':
        final localId = _localIdByKey[key] ?? int.tryParse(record.recordId);
        if (localId != null) {
          await (_db.delete(_db.attendance)..where((t) => t.id.equals(localId))).go();
        }
        break;
      default:
        break;
    }
  }

  Future<void> _applyTests(ChangeSetRecord record, Map<String, dynamic> payload) async {
    final key = _key('tests', record.recordId);
    switch (record.operation) {
      case 'INSERT':
        final studentId = payload['studentId'] as int?;
        final score = payload['score'] as int? ?? 0;
        if (studentId == null) return;
        final id = await _db.into(_db.tests).insert(
          TestsCompanion.insert(
            studentId: studentId,
            score: score,
            label: _optValue<String>(payload['label']),
            subjectId: payload['subjectId'] != null ? Value(payload['subjectId'] as int) : const Value.absent(),
            createdAt: Value(DateTime.now()),
            academicSession: _optValue<String>(payload['academicSession']),
          ),
        );
        _localIdByKey[key] = id;
        break;
      case 'UPDATE':
        final localId = _localIdByKey[key] ?? int.tryParse(record.recordId);
        if (localId == null) return;
        await (_db.update(_db.tests)..where((t) => t.id.equals(localId))).write(
          TestsCompanion(
            score: payload['score'] != null ? Value(payload['score'] as int) : const Value.absent(),
            label: _optValue<String>(payload['label']),
            subjectId: payload['subjectId'] != null ? Value(payload['subjectId'] as int) : const Value.absent(),
            updatedAt: Value(DateTime.now()),
            academicSession: _optValue<String>(payload['academicSession']),
          ),
        );
        break;
      case 'DELETE':
        final localId = _localIdByKey[key] ?? int.tryParse(record.recordId);
        if (localId != null) {
          await (_db.delete(_db.tests)..where((t) => t.id.equals(localId))).go();
        }
        break;
      default:
        break;
    }
  }

  Future<void> _applyPayments(ChangeSetRecord record, Map<String, dynamic> payload) async {
    final studentId = payload['studentId'] as int?;
    final year = payload['year'] as String?;
    if (studentId == null || year == null) return;
    final key = _key('payments', record.recordId);
    double getDouble(String k) => (payload[k] is num) ? (payload[k] as num).toDouble() : 0.0;
    switch (record.operation) {
      case 'INSERT':
      case 'UPDATE':
        final existing = await (_db.select(_db.payments)
              ..where((t) => t.studentId.equals(studentId) & t.year.equals(year)))
            .getSingleOrNull();
        if (existing != null) {
          await (_db.update(_db.payments)..where((t) => t.id.equals(existing.id))).write(
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
              updatedAt: Value(DateTime.now()),
            ),
          );
          _localIdByKey[key] = existing.id;
          await _storeMapping('payments', record.recordId, existing.id);
        } else {
          final id = await _db.into(_db.payments).insert(
            PaymentsCompanion.insert(
              studentId: studentId,
              year: year,
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
            ),
          );
          _localIdByKey[key] = id;
          await _storeMapping('payments', record.recordId, id);
        }
        break;
      case 'DELETE':
        final localId = _localIdByKey[key] ?? await _getLocalId('payments', record.recordId) ?? int.tryParse(record.recordId);
        if (localId != null) {
          await (_db.delete(_db.payments)..where((t) => t.id.equals(localId))).go();
        }
        break;
      default:
        break;
    }
  }

  Future<void> _applySubjects(ChangeSetRecord record, Map<String, dynamic> payload) async {
    final key = _key('subjects', record.recordId);
    switch (record.operation) {
      case 'INSERT':
        final name = payload['name'] as String?;
        final classId = payload['classId'] is int
            ? payload['classId'] as int
            : (payload['classId'] as num?)?.toInt();
        if (name == null || classId == null) return;
        final id = await _db.into(_db.subjects).insert(
          SubjectsCompanion.insert(name: name, classId: classId),
        );
        _localIdByKey[key] = id;
        break;
      case 'UPDATE':
        final localId = _localIdByKey[key] ?? int.tryParse(record.recordId);
        if (localId == null) return;
        final name = payload['name'] as String?;
        if (name != null) {
          await (_db.update(_db.subjects)..where((t) => t.id.equals(localId))).write(
            SubjectsCompanion(name: Value(name)),
          );
        }
        break;
      case 'DELETE':
        final localId = _localIdByKey[key] ?? int.tryParse(record.recordId);
        if (localId != null) {
          await (_db.delete(_db.subjects)..where((t) => t.id.equals(localId))).go();
        }
        break;
      default:
        break;
    }
  }

  Future<void> _applyMissions(ChangeSetRecord record, Map<String, dynamic> payload) async {
    final key = _key('missions', record.recordId);
    switch (record.operation) {
      case 'INSERT':
        final title = payload['title'] as String?;
        final location = payload['location'] as String?;
        final year = payload['year'] as String?;
        final mode = payload['mode'] as String?;
        if (title == null || location == null || year == null || mode == null) return;
        final startDate = payload['startDate'] != null
            ? DateTime.parse(payload['startDate'] as String)
            : DateTime.now();
        final endDate = payload['endDate'] != null
            ? DateTime.parse(payload['endDate'] as String)
            : DateTime.now();
        final slotsTotal = payload['slotsTotal'] as int? ?? 1;
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
            amount: payload['amount'] != null ? Value((payload['amount'] as num).toDouble()) : const Value.absent(),
          ),
        );
        _localIdByKey[key] = id;
        break;
      case 'UPDATE':
        final localId = _localIdByKey[key] ?? int.tryParse(record.recordId);
        if (localId == null) return;
        final comp = MissionsCompanion(
          title: _optValue<String>(payload['title']),
          location: _optValue<String>(payload['location']),
          startDate: payload['startDate'] != null ? Value(DateTime.parse(payload['startDate'] as String)) : const Value.absent(),
          endDate: payload['endDate'] != null ? Value(DateTime.parse(payload['endDate'] as String)) : const Value.absent(),
          slotsTotal: payload['slotsTotal'] != null ? Value(payload['slotsTotal'] as int) : const Value.absent(),
          description: _optValue<String>(payload['description']),
          isActive: payload['isActive'] != null ? Value(payload['isActive'] as bool) : const Value.absent(),
          year: _optValue<String>(payload['year']),
          mode: _optValue<String>(payload['mode']),
          amount: payload['amount'] != null ? Value((payload['amount'] as num).toDouble()) : const Value.absent(),
          updatedAt: Value(DateTime.now()),
        );
        await (_db.update(_db.missions)..where((t) => t.id.equals(localId))).write(comp);
        break;
      case 'DELETE':
        final localId = _localIdByKey[key] ?? int.tryParse(record.recordId);
        if (localId != null) {
          await (_db.delete(_db.missions)..where((t) => t.id.equals(localId))).go();
        }
        break;
      default:
        break;
    }
  }

  Value<T> _optValue<T>(dynamic v) {
    if (v == null) return Value.absent();
    return Value(v as T);
  }
}
