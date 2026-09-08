import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/services/change_set_applier.dart';
import 'package:charis_student_care/data/services/change_set_sync_service.dart';
import 'package:drift/drift.dart' hide isNotNull;

void main() {
  late AppDatabase db;
  late ChangeSetApplier applier;

  setUp(() {
    db = AppDatabase.test();
    applier = ChangeSetApplier(db);
  });

  tearDown(() async {
    await db.close();
  });

  ChangeSetRecord record({
    required String table,
    required String recordId,
    required String operation,
    required String payload,
    String id = 'cs-1',
  }) {
    return ChangeSetRecord(
      id: id,
      table: table,
      recordId: recordId,
      operation: operation,
      payload: payload,
      timestamp: DateTime.utc(2026, 1, 1),
      userId: 'u1',
      version: 1,
      deviceId: 'device-a',
    );
  }

  test('skips unsupported tables without marking applied', () async {
    final result = await applier.tryApply(
      record(
        table: 'unknown_table',
        recordId: '1',
        operation: 'INSERT',
        payload: '{"name":"X"}',
      ),
    );
    expect(result, isA<ApplyResultSkipped>());
    expect((result as ApplyResultSkipped).permanent, isTrue);
    final count = await db.select(db.changeSets).get();
    expect(count, isEmpty);
  });

  test('skips corrupt payload without marking applied', () async {
    final result = await applier.tryApply(
      record(
        table: 'students',
        recordId: '1',
        operation: 'INSERT',
        payload: 'not-json',
      ),
    );
    expect(result, isA<ApplyResultSkipped>());
    expect((result as ApplyResultSkipped).permanent, isTrue);
  });

  test('remaps student id for payment apply', () async {
    final localStudentId = await db.into(db.students).insert(
          StudentsCompanion.insert(
            surname: 'Doe',
            firstName: 'Jane',
          ),
        );
    await db.into(db.syncRecordMapping).insert(
          SyncRecordMappingCompanion.insert(
            entityTable: 'students',
            recordId: '99',
            localId: localStudentId,
          ),
        );

    final result = await applier.tryApply(
      record(
        id: 'pay-1',
        table: 'payments',
        recordId: '500',
        operation: 'INSERT',
        payload:
            '{"studentId":99,"year":"2026","academicSession":"2026","feb":100.0,"lumpSum":0}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    final payments = await db.select(db.payments).get();
    expect(payments.length, 1);
    expect(payments.first.studentId, localStudentId);
    expect(payments.first.feb, 100.0);
  });

  test('payment INSERT succeeds when created_at has no SQL default', () async {
    await db.customStatement('DROP TABLE IF EXISTS payments');
    await db.customStatement('''
      CREATE TABLE payments (
        id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
        student_id INTEGER NOT NULL,
        year TEXT NOT NULL,
        jan REAL NOT NULL DEFAULT 0,
        feb REAL NOT NULL DEFAULT 0,
        mar REAL NOT NULL DEFAULT 0,
        apr REAL NOT NULL DEFAULT 0,
        may REAL NOT NULL DEFAULT 0,
        jun REAL NOT NULL DEFAULT 0,
        jul REAL NOT NULL DEFAULT 0,
        aug REAL NOT NULL DEFAULT 0,
        sep REAL NOT NULL DEFAULT 0,
        oct REAL NOT NULL DEFAULT 0,
        nov REAL NOT NULL DEFAULT 0,
        dec REAL NOT NULL DEFAULT 0,
        lump_sum REAL NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        academic_session_id INTEGER,
        UNIQUE(student_id, year)
      )
    ''');

    final localStudentId = await db.into(db.students).insert(
          StudentsCompanion.insert(
            surname: 'Mpushe',
            firstName: 'Thembelani',
          ),
        );
    await db.into(db.syncRecordMapping).insert(
          SyncRecordMappingCompanion.insert(
            entityTable: 'students',
            recordId: '108',
            localId: localStudentId,
          ),
        );

    final result = await applier.tryApply(
      record(
        id: 'pay-legacy-1',
        table: 'payments',
        recordId: '500',
        operation: 'INSERT',
        payload: '{"studentId":108,"year":"2026","mar":450.0}',
      ),
    );

    expect(result, isA<ApplyResultApplied>());
    final payments = await db.select(db.payments).get();
    expect(payments, hasLength(1));
    expect(payments.single.studentId, localStudentId);
    expect(payments.single.mar, 450.0);
    expect(payments.single.createdAt, isNotNull);
    expect(payments.single.updatedAt, isNotNull);
  });

  test('applies mission_locations INSERT and stores mapping', () async {
    final result = await applier.tryApply(
      record(
        id: 'loc-1',
        table: 'mission_locations',
        recordId: '77',
        operation: 'INSERT',
        payload: '{"name":"Cape Town","description":"Coast","isActive":true}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    final locs = await db.select(db.missionLocations).get();
    expect(locs.length, 1);
    expect(locs.first.name, 'Cape Town');
    final mapping = await (db.select(db.syncRecordMapping)
          ..where((t) =>
              t.entityTable.equals('mission_locations') &
              t.recordId.equals('77'),))
        .getSingleOrNull();
    expect(mapping?.localId, locs.first.id);
  });

  test('applies participation with remapped mission and student ids', () async {
    final localStudentId = await db.into(db.students).insert(
          StudentsCompanion.insert(surname: 'Smith', firstName: 'Ann'),
        );
    final localMissionId = await db.into(db.missions).insert(
          MissionsCompanion.insert(
            title: 'Trip',
            location: 'Jozi',
            startDate: DateTime(2026, 3, 1),
            endDate: DateTime(2026, 3, 10),
            slotsTotal: 5,
            year: '2026',
            mode: 'Both',
          ),
        );
    await db.into(db.syncRecordMapping).insert(
          SyncRecordMappingCompanion.insert(
            entityTable: 'students',
            recordId: '201',
            localId: localStudentId,
          ),
        );
    await db.into(db.syncRecordMapping).insert(
          SyncRecordMappingCompanion.insert(
            entityTable: 'missions',
            recordId: '301',
            localId: localMissionId,
          ),
        );

    final result = await applier.tryApply(
      record(
        id: 'part-1',
        table: 'mission_participations',
        recordId: '401',
        operation: 'INSERT',
        payload:
            '{"missionId":301,"studentId":201,"role":"Volunteer","amount":500.0}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    final parts = await db.select(db.missionParticipations).get();
    expect(parts.length, 1);
    expect(parts.first.missionId, localMissionId);
    expect(parts.first.studentId, localStudentId);
    expect(parts.first.role, 'Volunteer');
    expect(parts.first.amount, 500.0);
  });

  test('applies mission payment against remapped participation', () async {
    final studentId = await db.into(db.students).insert(
          StudentsCompanion.insert(surname: 'Lee', firstName: 'Bo'),
        );
    final missionId = await db.into(db.missions).insert(
          MissionsCompanion.insert(
            title: 'Trip',
            location: 'Durban',
            startDate: DateTime(2026, 4, 1),
            endDate: DateTime(2026, 4, 8),
            slotsTotal: 3,
            year: '2026',
            mode: 'Both',
          ),
        );
    final localPartId = await db.into(db.missionParticipations).insert(
          MissionParticipationsCompanion.insert(
            missionId: missionId,
            studentId: studentId,
            role: 'Participant',
            amount: const Value(1000.0),
          ),
        );
    await db.into(db.syncRecordMapping).insert(
          SyncRecordMappingCompanion.insert(
            entityTable: 'mission_participations',
            recordId: '901',
            localId: localPartId,
          ),
        );

    final result = await applier.tryApply(
      record(
        id: 'mpay-1',
        table: 'mission_payments',
        recordId: '902',
        operation: 'INSERT',
        payload:
            '{"missionParticipationId":901,"paymentDate":"2026-04-15T00:00:00.000","amount":250.0,"academicSession":"2026"}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    final pays = await db.select(db.missionPayments).get();
    expect(pays.length, 1);
    expect(pays.first.missionParticipationId, localPartId);
    expect(pays.first.amount, 250.0);
  });

  test('applies schedule row with remapped student id', () async {
    final localStudentId = await db.into(db.students).insert(
          StudentsCompanion.insert(surname: 'Ng', firstName: 'Kim'),
        );
    await db.into(db.syncRecordMapping).insert(
          SyncRecordMappingCompanion.insert(
            entityTable: 'students',
            recordId: '55',
            localId: localStudentId,
          ),
        );

    final result = await applier.tryApply(
      record(
        id: 'sched-1',
        table: 'mission_payment_schedule',
        recordId: '800',
        operation: 'INSERT',
        payload:
            '{"studentId":55,"year":"2026","academicSession":"2026","amount":1200.0,"mar":100.0,"apr":100.0,"tripSelected":"Cape"}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    final rows = await db.select(db.missionPaymentSchedule).get();
    expect(rows.length, 1);
    expect(rows.first.studentId, localStudentId);
    expect(rows.first.year, '2026');
    expect(rows.first.amount, 1200.0);
    expect(rows.first.mar, 100.0);
    expect(rows.first.tripSelected, 'Cape');
  });

  test('skips no-op apply without marking applied', () async {
    final result = await applier.tryApply(
      record(
        id: 'noop-1',
        table: 'missions',
        recordId: '1',
        operation: 'INSERT',
        payload: '{"title":"Only title"}',
      ),
    );
    expect(result, isA<ApplyResultSkipped>());
    final count = await db.select(db.changeSets).get();
    expect(count, isEmpty);
    final missions = await db.select(db.missions).get();
    expect(missions, isEmpty);
  });

  test('DELETE tests with recordId all clears all tests', () async {
    final studentId = await db.into(db.students).insert(
          StudentsCompanion.insert(surname: 'A', firstName: 'B'),
        );
    await db.into(db.tests).insert(
          TestsCompanion.insert(
            studentId: studentId,
            score: 80,
          ),
        );
    await db.into(db.tests).insert(
          TestsCompanion.insert(
            studentId: studentId,
            score: 70,
          ),
        );
    expect((await db.select(db.tests).get()).length, 2);

    final result = await applier.tryApply(
      record(
        id: 'clear-tests',
        table: 'tests',
        recordId: 'all',
        operation: 'DELETE',
        payload: '{}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    expect(await db.select(db.tests).get(), isEmpty);
  });

  test('student INSERT resolves classId by className, not remote id', () async {
    final year1 = (await db.select(db.classes).get())
        .firstWhere((c) => c.name == 'Year 1');
    final remoteWrongClassId = year1.id + 999;

    final result = await applier.tryApply(
      record(
        id: 'stu-class-1',
        table: 'students',
        recordId: 'remote-student-1',
        operation: 'INSERT',
        payload:
            '{"surname":"Smith","firstName":"Ada","classId":$remoteWrongClassId,"className":"Year 1","mode":"Full-time"}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    final students = await db.select(db.students).get();
    expect(students, hasLength(1));
    expect(students.single.classId, year1.id);
  });

  test('student INSERT with only remote classId leaves class empty', () async {
    final result = await applier.tryApply(
      record(
        id: 'stu-class-2',
        table: 'students',
        recordId: 'remote-student-2',
        operation: 'INSERT',
        payload:
            '{"surname":"NoClass","firstName":"Name","classId":99999,"mode":"Full-time"}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    final students = await db.select(db.students).get();
    expect(students, hasLength(1));
    expect(students.single.classId, equals(null));
  });

  test('subject INSERT resolves class by className', () async {
    final year2 = (await db.select(db.classes).get())
        .firstWhere((c) => c.name == 'Year 2');

    final result = await applier.tryApply(
      record(
        id: 'subj-1',
        table: 'subjects',
        recordId: 'remote-subj-1',
        operation: 'INSERT',
        payload: '{"name":"Math","classId":12345,"className":"Year 2"}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    final subjects = await db.select(db.subjects).get();
    final math = subjects.where((s) => s.name == 'Math').toList();
    expect(math, hasLength(1));
    expect(math.single.classId, year2.id);
  });

  test('class INSERT merges onto seeded Year 1 by name and maps remote id',
      () async {
    final year1 = (await db.select(db.classes).get())
        .firstWhere((c) => c.name == 'Year 1');
    final result = await applier.tryApply(
      record(
        id: 'class-1',
        table: 'classes',
        recordId: 'remote-class-99',
        operation: 'INSERT',
        payload: '{"name":"Year 1","sortOrder":1}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    final classes = await db.select(db.classes).get();
    expect(classes.where((c) => c.name == 'Year 1'), hasLength(1));
    final mapping = await (db.select(db.syncRecordMapping)
          ..where((t) =>
              t.entityTable.equals('classes') &
              t.recordId.equals('remote-class-99'),))
        .getSingleOrNull();
    expect(mapping?.localId, year1.id);
  });

  test('academic session INSERT by code upserts and settings current flips active',
      () async {
    final result = await applier.tryApply(
      record(
        id: 'sess-1',
        table: 'academic_sessions',
        recordId: 'remote-sess-1',
        operation: 'INSERT',
        payload: '{"code":"2099","isActive":false,"displayName":"Year 2099"}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    final sessions = await db.select(db.academicSessions).get();
    expect(sessions.any((s) => s.code == '2099'), isTrue);

    final settingsResult = await applier.tryApply(
      record(
        id: 'set-current',
        table: 'app_settings',
        recordId: 'current_academic_session',
        operation: 'UPDATE',
        payload:
            '{"key":"current_academic_session","value":"2099","updatedAt":"2026-01-01T00:00:00.000Z"}',
      ),
    );
    expect(settingsResult, isA<ApplyResultApplied>());
    final active = await (db.select(db.academicSessions)
          ..where((t) => t.code.equals('2099')))
        .getSingle();
    expect(active.isActive, isTrue);
    final setting = await (db.select(db.appSettings)
          ..where((s) => s.key.equals('current_academic_session')))
        .getSingleOrNull();
    expect(setting?.value, '2099');
  });

  test('user INSERT by username upserts hash/role and remaps allowedClassName',
      () async {
    final year1 = (await db.select(db.classes).get())
        .firstWhere((c) => c.name == 'Year 1');
    final result = await applier.tryApply(
      record(
        id: 'user-1',
        table: 'users',
        recordId: 'remote-user-1',
        operation: 'INSERT',
        payload:
            '{"username":"sync_facilitator","passwordHash":"\$2a\$10\$abcdefghijklmnopqrstuu","role":"facilitator","isActive":true,"allowedClassName":"Year 1","allowedMode":"Full-time","updatedAt":1,"createdAt":1}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    final users = await db.select(db.users).get();
    final u = users.firstWhere((x) => x.username == 'sync_facilitator');
    expect(u.role, 'facilitator');
    expect(u.allowedClassId, year1.id);
    expect(u.allowedMode, 'Full-time');

    final update = await applier.tryApply(
      record(
        id: 'user-2',
        table: 'users',
        recordId: 'remote-user-1',
        operation: 'UPDATE',
        payload:
            '{"username":"sync_facilitator","passwordHash":"\$2a\$10\$abcdefghijklmnopqrstuu","role":"facilitator","isActive":false,"allowedClassName":"Year 1","updatedAt":2,"createdAt":1}',
      ),
    );
    expect(update, isA<ApplyResultApplied>());
    final updated = await (db.select(db.users)
          ..where((t) => t.username.equals('sync_facilitator')))
        .getSingle();
    expect(updated.isActive, isFalse);
  });

  test('settings tuition upsert; onedrive_url ignored permanently', () async {
    final tuition = await applier.tryApply(
      record(
        id: 'tuition-1',
        table: 'app_settings',
        recordId: 'monthly_tuition_fee',
        operation: 'UPDATE',
        payload:
            '{"key":"monthly_tuition_fee","value":"2500.0","updatedAt":"2026-01-01T00:00:00.000Z"}',
      ),
    );
    expect(tuition, isA<ApplyResultApplied>());
    final row = await (db.select(db.appSettings)
          ..where((s) => s.key.equals('monthly_tuition_fee')))
        .getSingleOrNull();
    expect(row?.value, '2500.0');

    final ignored = await applier.tryApply(
      record(
        id: 'od-1',
        table: 'app_settings',
        recordId: 'onedrive_url',
        operation: 'UPDATE',
        payload:
            '{"key":"onedrive_url","value":"https://evil.example","updatedAt":"2026-01-01T00:00:00.000Z"}',
      ),
    );
    expect(ignored, isA<ApplyResultSkipped>());
    expect((ignored as ApplyResultSkipped).permanent, isTrue);
    final od = await (db.select(db.appSettings)
          ..where((s) => s.key.equals('onedrive_url')))
        .getSingleOrNull();
    expect(od, equals(null));
  });

  test('student UPDATE with className promotes class across devices', () async {
    final year1 = (await db.select(db.classes).get())
        .firstWhere((c) => c.name == 'Year 1');
    final year2 = (await db.select(db.classes).get())
        .firstWhere((c) => c.name == 'Year 2');
    final localId = await db.into(db.students).insert(
          StudentsCompanion.insert(
            surname: 'Promote',
            firstName: 'Me',
            classId: Value(year1.id),
            version: const Value(1),
          ),
        );
    await db.into(db.syncRecordMapping).insert(
          SyncRecordMappingCompanion.insert(
            entityTable: 'students',
            recordId: 'remote-promote-1',
            localId: localId,
          ),
        );

    final result = await applier.tryApply(
      record(
        id: 'promote-1',
        table: 'students',
        recordId: 'remote-promote-1',
        operation: 'UPDATE',
        payload:
            '{"className":"Year 2","baseVersion":1,"version":2}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    final student =
        await (db.select(db.students)..where((t) => t.id.equals(localId)))
            .getSingle();
    expect(student.classId, year2.id);
  });

  test('ministry entry INSERT resolves class via className', () async {
    final year1 = (await db.select(db.classes).get())
        .firstWhere((c) => c.name == 'Year 1');
    final studentId = await db.into(db.students).insert(
          StudentsCompanion.insert(
            surname: 'Ministry',
            firstName: 'Student',
          ),
        );
    await db.into(db.syncRecordMapping).insert(
          SyncRecordMappingCompanion.insert(
            entityTable: 'students',
            recordId: '55',
            localId: studentId,
          ),
        );

    final result = await applier.tryApply(
      record(
        id: 'min-1',
        table: 'ministry_entries',
        recordId: 'remote-min-1',
        operation: 'INSERT',
        payload:
            '{"studentId":55,"year":"2026","term":1,"className":"Year 1","ministryType":"Church","date":"2026-03-01T00:00:00.000","hours":2.0,"approved":false}',
      ),
    );
    expect(result, isA<ApplyResultApplied>());
    final entries = await db.select(db.ministryEntries).get();
    expect(entries, hasLength(1));
    expect(entries.single.classId, year1.id);
  });
}
