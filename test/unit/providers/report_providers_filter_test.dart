import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/database_provider.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/report_providers.dart';
import 'package:charis_student_care/presentation/providers/settings_providers.dart';

void main() {
  late AppDatabase database;
  late ProviderContainer container;

  setUp(() async {
    database = AppDatabase.test();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        currentUserFacilitatorScopeProvider.overrideWith((ref) async => null),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  test('studentsReportDataProvider excludes withdrawn students by default', () async {
    await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Active',
            firstName: 'Student',
            mode: const Value('Full-time'),
          ),
        );
    await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Withdrawn',
            firstName: 'Student',
            status: const Value('Withdrawn'),
            mode: const Value('Full-time'),
          ),
        );

    final filters = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 1, 1),
      dateEnd: DateTime(2026, 12, 31),
    );

    final rows = await container.read(studentsReportDataProvider(filters).future);
    expect(rows, hasLength(1));
    expect(rows.single.student.surname, 'Active');
  });

  test('paymentsReportDataProvider excludes withdrawn students by default', () async {
    final activeId = await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Active',
            firstName: 'Paying',
            mode: const Value('Full-time'),
          ),
        );
    final withdrawnId = await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Withdrawn',
            firstName: 'Paying',
            status: const Value('Withdrawn'),
            mode: const Value('Full-time'),
          ),
        );

    await database.into(database.payments).insert(
          PaymentsCompanion.insert(
            studentId: activeId,
            year: '2026',
            jan: const Value(100),
          ),
        );
    await database.into(database.payments).insert(
          PaymentsCompanion.insert(
            studentId: withdrawnId,
            year: '2026',
            jan: const Value(100),
          ),
        );

    final filters = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 1, 1),
      dateEnd: DateTime(2026, 12, 31),
    );

    final rows = await container.read(paymentsReportDataProvider(filters).future);
    expect(rows, hasLength(1));
    expect(rows.single.studentName, contains('Active'));
  });

  test('studentsReportDataProvider intersects facilitator scope with class filter',
      () async {
    final classes = await database.select(database.classes).get();
    final year1 = classes.firstWhere((c) => c.name == 'Year 1');
    final year2 = classes.firstWhere((c) => c.name == 'Year 2');

    await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'InScope',
            firstName: 'Y1',
            mode: const Value('Full-time'),
            classId: Value(year1.id),
          ),
        );
    await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'OtherClass',
            firstName: 'Y2',
            mode: const Value('Full-time'),
            classId: Value(year2.id),
          ),
        );

    container.dispose();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        currentUserFacilitatorScopeProvider.overrideWith(
          (ref) async => FacilitatorScope(
            classIds: [year1.id, year2.id],
            mode: null,
          ),
        ),
      ],
    );

    final filters = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 1, 1),
      dateEnd: DateTime(2026, 12, 31),
      classFilter: 'Year 1',
    );

    final rows =
        await container.read(studentsReportDataProvider(filters).future);
    expect(rows, hasLength(1));
    expect(rows.single.student.surname, 'InScope');
  });

  test('missionPaymentsReportDataProvider respects allow-list and active-only',
      () async {
    final classes = await database.select(database.classes).get();
    final year1 = classes.firstWhere((c) => c.name == 'Year 1');

    final activeId = await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Active',
            firstName: 'Pay',
            mode: const Value('Full-time'),
            classId: Value(year1.id),
          ),
        );
    final withdrawnId = await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Withdrawn',
            firstName: 'Pay',
            status: const Value('Withdrawn'),
            mode: const Value('Full-time'),
            classId: Value(year1.id),
          ),
        );

    final missionId = await database.into(database.missions).insert(
          MissionsCompanion.insert(
            title: 'Trip',
            location: 'Here',
            startDate: DateTime(2026, 6, 1),
            endDate: DateTime(2026, 6, 10),
            slotsTotal: 10,
            year: '2026',
            mode: 'Full-time',
          ),
        );
    final activePart = await database.into(database.missionParticipations).insert(
          MissionParticipationsCompanion.insert(
            missionId: missionId,
            studentId: activeId,
            role: 'Volunteer',
            amount: const Value(100),
          ),
        );
    final withdrawnPart =
        await database.into(database.missionParticipations).insert(
              MissionParticipationsCompanion.insert(
                missionId: missionId,
                studentId: withdrawnId,
                role: 'Volunteer',
                amount: const Value(100),
              ),
            );
    await database.into(database.missionPayments).insert(
          MissionPaymentsCompanion.insert(
            missionParticipationId: activePart,
            paymentDate: DateTime(2026, 3, 1),
            amount: 50,
          ),
        );
    await database.into(database.missionPayments).insert(
          MissionPaymentsCompanion.insert(
            missionParticipationId: withdrawnPart,
            paymentDate: DateTime(2026, 3, 2),
            amount: 50,
          ),
        );

    final filters = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 1, 1),
      dateEnd: DateTime(2026, 12, 31),
    );

    final rows =
        await container.read(missionPaymentsReportDataProvider(filters).future);
    expect(rows, hasLength(1));
    expect(rows.single.studentName, contains('Active'));
  });

  test('attendanceReportDataProvider filters by academicSessionId', () async {
    final sessions = await database.select(database.academicSessions).get();
    final session2026 = sessions.firstWhere((s) => s.code == '2026');
    final session2025 = sessions.firstWhere((s) => s.code == '2025');
    final studentId = await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Att',
            firstName: 'Student',
            mode: const Value('Full-time'),
          ),
        );
    await database.into(database.attendance).insert(
          AttendanceCompanion.insert(
            studentId: studentId,
            date: DateTime.utc(2026, 3, 1),
            present: const Value(1),
            academicSessionId: Value(session2026.id),
          ),
        );
    await database.into(database.attendance).insert(
          AttendanceCompanion.insert(
            studentId: studentId,
            date: DateTime.utc(2026, 3, 2),
            present: const Value(1),
            academicSessionId: Value(session2025.id),
          ),
        );

    final filters = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 1, 1),
      dateEnd: DateTime(2026, 12, 31),
      academicSession: '2026',
    );

    final rows =
        await container.read(attendanceReportDataProvider(filters).future);
    expect(rows, hasLength(1));
    expect(rows.single.date.day, 1);
  });

  test('reportDataProvider excludes students with no in-range activity', () async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        currentUserFacilitatorScopeProvider.overrideWith((ref) async => null),
        sessionTuitionAmountProvider.overrideWith((ref) => 10000.0),
      ],
    );

    final withActivity = await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'HasData',
            firstName: 'Student',
            mode: const Value('Full-time'),
          ),
        );
    await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'NoData',
            firstName: 'Student',
            mode: const Value('Full-time'),
          ),
        );
    await database.into(database.attendance).insert(
          AttendanceCompanion.insert(
            studentId: withActivity,
            date: DateTime.utc(2026, 3, 10),
            present: const Value(1),
          ),
        );

    final filters = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 1, 1),
      dateEnd: DateTime(2026, 12, 31),
    );

    final rows = await container.read(reportDataProvider(filters).future);
    expect(rows, hasLength(1));
    expect(rows.single.student.surname, 'HasData');
  });

  test('reportDataProvider applies session to attendance like Attendance report',
      () async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        currentUserFacilitatorScopeProvider.overrideWith((ref) async => null),
        sessionTuitionAmountProvider.overrideWith((ref) => 10000.0),
      ],
    );

    final sessions = await database.select(database.academicSessions).get();
    final session2026 = sessions.firstWhere((s) => s.code == '2026');
    final session2025 = sessions.firstWhere((s) => s.code == '2025');

    final studentId = await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Session',
            firstName: 'Filter',
            mode: const Value('Full-time'),
          ),
        );
    await database.into(database.attendance).insert(
          AttendanceCompanion.insert(
            studentId: studentId,
            date: DateTime.utc(2026, 4, 1),
            present: const Value(1),
            academicSessionId: Value(session2026.id),
          ),
        );
    await database.into(database.attendance).insert(
          AttendanceCompanion.insert(
            studentId: studentId,
            date: DateTime.utc(2026, 4, 2),
            present: const Value(1),
            academicSessionId: Value(session2025.id),
          ),
        );

    final filters = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 1, 1),
      dateEnd: DateTime(2026, 12, 31),
      academicSession: '2026',
    );

    final rows = await container.read(reportDataProvider(filters).future);
    expect(rows, hasLength(1));
    expect(rows.single.attendanceTotalDays, 1);
  });

  test('studentsReportDataProvider denies class filter outside facilitator scope',
      () async {
    final classes = await database.select(database.classes).get();
    final year1 = classes.firstWhere((c) => c.name == 'Year 1');
    final year2 = classes.firstWhere((c) => c.name == 'Year 2');

    await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Scoped',
            firstName: 'Y1',
            mode: const Value('Full-time'),
            classId: Value(year1.id),
          ),
        );
    await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Outside',
            firstName: 'Y2',
            mode: const Value('Full-time'),
            classId: Value(year2.id),
          ),
        );

    container.dispose();
    container = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        currentUserFacilitatorScopeProvider.overrideWith(
          (ref) async => FacilitatorScope(
            classIds: [year1.id],
            mode: null,
          ),
        ),
      ],
    );

    final filters = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 1, 1),
      dateEnd: DateTime(2026, 12, 31),
      classFilter: 'Year 2',
    );

    final rows =
        await container.read(studentsReportDataProvider(filters).future);
    expect(rows, isEmpty);
  });
}

