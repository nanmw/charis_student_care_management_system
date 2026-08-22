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

  test('missionPaymentsReportDataProvider exports schedule grid and skips withdrawn',
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

    await database.into(database.missionPaymentSchedule).insert(
          MissionPaymentScheduleCompanion.insert(
            studentId: activeId,
            year: '2026',
            tripSelected: const Value('Cape Town'),
            amount: const Value(1000),
            mar: const Value(250),
          ),
        );
    await database.into(database.missionPaymentSchedule).insert(
          MissionPaymentScheduleCompanion.insert(
            studentId: withdrawnId,
            year: '2026',
            amount: const Value(1000),
            mar: const Value(250),
          ),
        );

    final filters = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 1, 1),
      dateEnd: DateTime(2026, 12, 31),
      academicSession: '2026',
    );

    final rows =
        await container.read(missionPaymentsReportDataProvider(filters).future);
    expect(rows, hasLength(1));
    expect(rows.single.studentName, contains('Active'));
    expect(rows.single.tripSelected, 'Cape Town');
    expect(rows.single.paidToDate, 250);
    expect(rows.single.balance, 750);
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
    await database.into(database.attendance).insert(
          AttendanceCompanion.insert(
            studentId: studentId,
            date: DateTime.utc(2026, 3, 3),
            present: const Value(1),
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
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.date.day).toSet(), {1, 3});
  });

  test('ministryReportDataProvider includes unscoped rows for selected session',
      () async {
    final sessions = await database.select(database.academicSessions).get();
    final session2026 = sessions.firstWhere((s) => s.code == '2026');
    final session2025 = sessions.firstWhere((s) => s.code == '2025');
    final studentId = await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Min',
            firstName: 'Student',
            mode: const Value('Full-time'),
          ),
        );
    await database.into(database.ministryEntries).insert(
          MinistryEntriesCompanion.insert(
            studentId: studentId,
            year: '2026',
            term: 1,
            ministryType: 'Community Service',
            date: DateTime.utc(2026, 3, 1),
            hours: 2,
            academicSessionId: Value(session2026.id),
          ),
        );
    await database.into(database.ministryEntries).insert(
          MinistryEntriesCompanion.insert(
            studentId: studentId,
            year: '2025',
            term: 1,
            ministryType: 'Evangelism',
            date: DateTime.utc(2026, 3, 2),
            hours: 3,
            academicSessionId: Value(session2025.id),
          ),
        );
    await database.into(database.ministryEntries).insert(
          MinistryEntriesCompanion.insert(
            studentId: studentId,
            year: '2026',
            term: 1,
            ministryType: 'Outreach',
            date: DateTime.utc(2026, 3, 3),
            hours: 4,
          ),
        );

    final filters = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 1, 1),
      dateEnd: DateTime(2026, 12, 31),
      academicSession: '2026',
    );

    final rows =
        await container.read(ministryReportDataProvider(filters).future);
    expect(rows, hasLength(2));
    expect(rows.map((r) => r.ministryType).toSet(), {
      'Community Service',
      'Outreach',
    });
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

  test('attendanceReportDataProvider respects date range', () async {
    final studentId = await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Range',
            firstName: 'Att',
            mode: const Value('Full-time'),
          ),
        );
    await database.into(database.attendance).insert(
          AttendanceCompanion.insert(
            studentId: studentId,
            date: DateTime.utc(2026, 3, 10),
            present: const Value(1),
          ),
        );
    await database.into(database.attendance).insert(
          AttendanceCompanion.insert(
            studentId: studentId,
            date: DateTime.utc(2026, 5, 10),
            present: const Value(1),
          ),
        );

    final filters = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 5, 1),
      dateEnd: DateTime(2026, 5, 31),
      academicSession: '2026',
    );

    final rows =
        await container.read(attendanceReportDataProvider(filters).future);
    expect(rows, hasLength(1));
    expect(rows.single.date.month, 5);
  });

  test('paymentsReportDataProvider totals only months in date range', () async {
    final studentId = await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Range',
            firstName: 'Pay',
            mode: const Value('Full-time'),
          ),
        );
    await database.into(database.payments).insert(
          PaymentsCompanion.insert(
            studentId: studentId,
            year: '2026',
            mar: const Value(40),
            may: const Value(60),
          ),
        );

    final filters = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 5, 1),
      dateEnd: DateTime(2026, 5, 31),
      academicSession: '2026',
    );

    final rows =
        await container.read(paymentsReportDataProvider(filters).future);
    expect(rows, hasLength(1));
    expect(rows.single.totalPaid, 60);
  });

  test('missionPaymentsReportDataProvider applies date range to trip date and months',
      () async {
    final studentId = await database.into(database.students).insert(
          StudentsCompanion.insert(
            surname: 'Trip',
            firstName: 'Date',
            mode: const Value('Full-time'),
          ),
        );
    await database.into(database.missionPaymentSchedule).insert(
          MissionPaymentScheduleCompanion.insert(
            studentId: studentId,
            year: '2026',
            date: Value(DateTime.utc(2026, 3, 15).millisecondsSinceEpoch),
            amount: const Value(1000),
            mar: const Value(250),
            oct: const Value(100),
          ),
        );

    final inRange = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 3, 1),
      dateEnd: DateTime(2026, 3, 31),
      academicSession: '2026',
    );
    final inRangeRows =
        await container.read(missionPaymentsReportDataProvider(inRange).future);
    expect(inRangeRows, hasLength(1));
    expect(inRangeRows.single.mar, 250);
    expect(inRangeRows.single.oct, 0);

    final outOfRange = ReportFilters(
      mode: 'Full-time',
      dateStart: DateTime(2026, 5, 1),
      dateEnd: DateTime(2026, 5, 31),
      academicSession: '2026',
    );
    final outRows = await container
        .read(missionPaymentsReportDataProvider(outOfRange).future);
    expect(outRows, isEmpty);
  });
}

