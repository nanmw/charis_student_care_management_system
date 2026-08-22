import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/academic_session_repository.dart';
import 'package:charis_student_care/data/repositories/attendance_repository.dart';

DateTime utcDay(int year, int month, int day) => DateTime.utc(year, month, day);

void main() {
  late AppDatabase db;
  late AttendanceRepository repo;

  setUp(() async {
    db = AppDatabase.test();
    repo = AttendanceRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('watchAttendanceInRange returns only dates inside the window', () async {
    final studentId = await db.into(db.students).insert(
          StudentsCompanion.insert(surname: 'Ada', firstName: 'Lovelace'),
        );
    await db.into(db.attendance).insert(
          AttendanceCompanion.insert(
            date: utcDay(2026, 1, 31),
            studentId: studentId,
            present: const Value(1),
          ),
        );
    await db.into(db.attendance).insert(
          AttendanceCompanion.insert(
            date: utcDay(2026, 2, 1),
            studentId: studentId,
            present: const Value(1),
          ),
        );
    await db.into(db.attendance).insert(
          AttendanceCompanion.insert(
            date: utcDay(2026, 4, 30),
            studentId: studentId,
            present: const Value(0),
          ),
        );
    await db.into(db.attendance).insert(
          AttendanceCompanion.insert(
            date: utcDay(2026, 5, 1),
            studentId: studentId,
            present: const Value(1),
          ),
        );

    final rows = await repo
        .watchAttendanceInRange(DateTime(2026, 2, 1), DateTime(2026, 4, 30))
        .first;
    expect(rows.length, 2);
    expect(
      rows.map((r) => DateTime.utc(r.date.year, r.date.month, r.date.day)),
      containsAll([utcDay(2026, 2, 1), utcDay(2026, 4, 30)]),
    );
  });

  test('watchAttendanceInRange with empty studentIds returns no rows', () async {
    final studentId = await db.into(db.students).insert(
          StudentsCompanion.insert(surname: 'Ada', firstName: 'Lovelace'),
        );
    await db.into(db.attendance).insert(
          AttendanceCompanion.insert(
            date: utcDay(2026, 2, 3),
            studentId: studentId,
            present: const Value(1),
          ),
        );

    final rows = await repo
        .watchAttendanceInRange(
          DateTime(2026, 2, 1),
          DateTime(2026, 2, 28),
          studentIds: const [],
        )
        .first;
    expect(rows, isEmpty);
  });

  test('upsertAttendanceRecords writes multiple dates and session id', () async {
    final sessionRepo = AcademicSessionRepository(db);
    await db.into(db.academicSessions).insert(
          AcademicSessionsCompanion.insert(code: '2026-test'),
        );
    final sessionId = await sessionRepo.getSessionIdByCode('2026-test');
    expect(sessionId, isNotNull);

    final studentA = await db.into(db.students).insert(
          StudentsCompanion.insert(surname: 'Ada', firstName: 'Lovelace'),
        );
    final studentB = await db.into(db.students).insert(
          StudentsCompanion.insert(surname: 'Grace', firstName: 'Hopper'),
        );

    await repo.upsertAttendanceRecords(
      [
        AttendanceRecordEntry(
          date: DateTime(2026, 2, 3),
          studentId: studentA,
          present: true,
          notes: 'Late',
        ),
        AttendanceRecordEntry(
          date: DateTime(2026, 2, 4),
          studentId: studentA,
          present: false,
        ),
        AttendanceRecordEntry(
          date: DateTime(2026, 2, 3),
          studentId: studentB,
          present: true,
        ),
      ],
      userRole: UserRole.adminLevel01,
      academicSessionId: sessionId,
    );

    final rows = await repo
        .watchAttendanceInRange(DateTime(2026, 2, 3), DateTime(2026, 2, 4))
        .first;
    expect(rows.length, 3);
    expect(
      rows.every((r) => r.academicSessionId == sessionId),
      isTrue,
    );

    final aFeb3 = rows.firstWhere(
      (r) => r.studentId == studentA && r.date.day == 3,
    );
    expect(aFeb3.present, 1);
    expect(aFeb3.notes, 'Late');

    await repo.upsertAttendanceRecords(
      [
        AttendanceRecordEntry(
          date: DateTime(2026, 2, 3),
          studentId: studentA,
          present: false,
          notes: null,
        ),
      ],
      userRole: UserRole.facilitator,
      academicSessionId: sessionId,
    );

    final updated = await repo
        .watchAttendanceInRange(DateTime(2026, 2, 3), DateTime(2026, 2, 3))
        .first;
    final aUpdated = updated.firstWhere((r) => r.studentId == studentA);
    expect(aUpdated.present, 0);
    expect(aUpdated.notes, isNull);
    expect(aUpdated.academicSessionId, sessionId);
  });
}
