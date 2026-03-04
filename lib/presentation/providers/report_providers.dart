import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/academic_session_repository.dart';
import 'package:charis_student_care/presentation/providers/academic_session_providers.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/dashboard_providers.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/repository_providers.dart';

/// Report type for the Export & Reports screen.
enum ReportType {
  studentSummary('Student Summary', 'student-summary'),
  cohortSummary('Dashboard – Cohort Summary', 'cohort-summary'),
  students('Students', 'students'),
  subjects('Subjects', 'subjects'),
  attendance('Attendance', 'attendance'),
  ministryHours('Ministry Hours', 'ministry-hours'),
  tests('Tests', 'tests'),
  payments('Payments', 'payments'),
  missionsPayment('Missions Payment', 'missions-payment'),
  missionLocations('Mission Locations', 'mission-locations');

  const ReportType(this.label, this.queryParam);
  final String label;
  final String queryParam;

  static ReportType fromQueryParam(String? value) {
    if (value == null || value.isEmpty) return ReportType.studentSummary;
    return ReportType.values.firstWhere(
      (e) => e.queryParam == value,
      orElse: () => ReportType.studentSummary,
    );
  }
}

/// One row for cohort summary report (mirrors DashboardCohortSummary for ReportService).
class CohortReportRow {
  const CohortReportRow({
    required this.year,
    required this.mode,
    required this.studentCount,
    this.avgAttendancePercent,
    required this.outstandingTests,
    required this.failedTests,
    required this.passedTests,
    required this.totalBalance,
  });
  final String year;
  final String mode;
  final int studentCount;
  final double? avgAttendancePercent;
  final int outstandingTests;
  final int failedTests;
  final int passedTests;
  final double totalBalance;
  String get cohortLabel => '$year / $mode';
}

/// Filters for the student summary report.
class ReportFilters {
  const ReportFilters({
    required this.mode,
    required this.dateStart,
    required this.dateEnd,
    this.year,
    this.academicSession,
    this.classFilter,
  });

  final String mode;
  final DateTime dateStart;
  final DateTime dateEnd;
  /// Optional year filter for students (e.g. admission year). When set, only students
  /// with this admission year are included. When null, all students matching mode are included.
  final String? year;
  /// Optional academic session code (e.g. 2024-2025). When set, session-based reports
  /// (payments, tests) filter by this session instead of raw year.
  final String? academicSession;
  /// Optional class filter (e.g. "Year 1", "Year 2", "Year 3"). When set, only students
  /// in that class are included. When null, year filter is used if set.
  final String? classFilter;
}

/// One row of aggregated data for the report (one per student).
class StudentReportRow {
  const StudentReportRow({
    required this.student,
    required this.attendanceTotalDays,
    required this.attendancePresentDays,
    required this.attendancePercentage,
    required this.testAverage,
    required this.testsPassed,
    required this.testsFailed,
    required this.totalPaid,
    required this.balance,
  });

  final Student student;
  final int attendanceTotalDays;
  final int attendancePresentDays;
  final double attendancePercentage;
  final double testAverage;
  final int testsPassed;
  final int testsFailed;
  final double totalPaid;
  final double balance;

  String get studentName => '${student.surname}, ${student.firstName}';
}

DateTime _dateOnly(DateTime d) => DateTime.utc(d.year, d.month, d.day);
DateTime _endOfDay(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day, 23, 59, 59, 999);

/// Returns allowed student ids when scope is set (facilitator); null means no filter (admin/portfolio lead).
Future<Set<int>?> _allowedStudentIdsForReport(AppDatabase db, FacilitatorScope? scope) async {
  if (scope == null || scope.classIds == null || scope.classIds!.isEmpty) return null;
  final students = await (db.select(db.students)
        ..where((t) {
          var p = t.classId.isIn(scope.classIds!);
          if (scope.mode != null && scope.mode!.trim().isNotEmpty) {
            p = p & t.mode.equals(scope.mode!.trim());
          }
          return p;
        }))
      .get();
  return students.map((s) => s.id).toSet();
}

/// Builds report rows for the given filters. Uses the database to query
/// attendance (in date range), tests (createdAt in date range), and payments
/// (for years overlapping the date range). When [classIds] is non-null and non-empty,
/// students are filtered by those classes; when [classId] is non-null, by that single class;
/// otherwise [filters.year] is used for admission year filter.
Future<List<StudentReportRow>> _buildReportRows(
  AppDatabase db,
  ReportFilters filters, {
  int? classId,
  List<int>? classIds,
}) async {
  final studentsQuery = db.select(db.students)
    ..where((t) {
      var p = t.status.equals('Active') & t.mode.equals(filters.mode);
      if (classIds != null && classIds.isNotEmpty) {
        p = p & t.classId.isIn(classIds);
      } else if (classId != null) {
        p = p & t.classId.equals(classId);
      } else if (filters.year != null && filters.year!.trim().isNotEmpty) {
        p = p & t.admissionYear.equals(filters.year!.trim());
      }
      return p;
    })
    ..orderBy([(t) => OrderingTerm.asc(t.surname), (t) => OrderingTerm.asc(t.firstName)]);
  final studentList = await studentsQuery.get();
  if (studentList.isEmpty) return [];

  final studentIds = studentList.map((s) => s.id).toList();
  final startDay = _dateOnly(filters.dateStart);
  final endDayOnly = _dateOnly(filters.dateEnd);
  final endDay = _endOfDay(filters.dateEnd);

  // Attendance in range (date column is date-only)
  final attendanceRows = await (db.select(db.attendance)
        ..where((t) =>
            t.studentId.isIn(studentIds) &
            t.date.isBiggerOrEqualValue(startDay) &
            t.date.isSmallerOrEqualValue(endDayOnly),))
      .get();

  final attendanceByStudent = <int, List<AttendanceData>>{};
  for (final a in attendanceRows) {
    attendanceByStudent.putIfAbsent(a.studentId, () => []).add(a);
  }

  // Tests in range (by createdAt)
  final testRows = await (db.select(db.tests)
        ..where((t) =>
            t.studentId.isIn(studentIds) &
            t.createdAt.isBiggerOrEqualValue(startDay) &
            t.createdAt.isSmallerOrEqualValue(endDay),))
      .get();

  final testsByStudent = <int, List<Test>>{};
  for (final t in testRows) {
    testsByStudent.putIfAbsent(t.studentId, () => []).add(t);
  }

  // Payments: years overlapping the date range
  final yearStart = filters.dateStart.year;
  final yearEnd = filters.dateEnd.year;
  final years = <String>{
    for (var y = yearStart; y <= yearEnd; y++) y.toString(),
  };
  final paymentRows = await (db.select(db.payments)
        ..where((t) =>
            t.studentId.isIn(studentIds) & t.year.isIn(years),))
      .get();

  final paymentByStudent = <int, double>{};
  for (final p in paymentRows) {
    final total = p.jan +
        p.feb +
        p.mar +
        p.apr +
        p.may +
        p.jun +
        p.jul +
        p.aug +
        p.sep +
        p.oct +
        p.nov +
        p.dec +
        p.lumpSum;
    paymentByStudent[p.studentId] =
        (paymentByStudent[p.studentId] ?? 0.0) + total;
  }

  const passThreshold = AppConstants.passingTestScore;
  const tuition = AppConstants.fullTuitionAmount;

  final rows = <StudentReportRow>[];
  for (final student in studentList) {
    final attList = attendanceByStudent[student.id] ?? [];
    final totalDays = attList.length;
    final presentDays = attList.where((a) => a.present == 1).length;
    final attPct =
        totalDays > 0 ? (presentDays / totalDays) * 100 : 0.0;

    final tList = testsByStudent[student.id] ?? [];
    final passed = tList.where((t) => t.score >= passThreshold).length;
    final failed = tList.where((t) => t.score < passThreshold).length;
    final avg = tList.isEmpty
        ? 0.0
        : tList.fold<int>(0, (s, t) => s + t.score) / tList.length;

    final paid = paymentByStudent[student.id] ?? 0.0;
    final balance = tuition - paid;

    rows.add(StudentReportRow(
      student: student,
      attendanceTotalDays: totalDays,
      attendancePresentDays: presentDays,
      attendancePercentage: attPct,
      testAverage: avg,
      testsPassed: passed,
      testsFailed: failed,
      totalPaid: paid,
      balance: balance,
    ),
  );
  }
  return rows;
}

/// Report data for the current filters. Scoped by facilitator scope when applicable.
final reportDataProvider =
    FutureProvider.autoDispose.family<List<StudentReportRow>, ReportFilters>(
  (ref, filters) async {
    final db = ref.watch(appDatabaseProvider);
    final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
    int? classId;
    List<int>? classIds;
    if (scope != null && scope.classIds != null && scope.classIds!.isNotEmpty) {
      classIds = scope.classIds;
    } else if (filters.classFilter != null && filters.classFilter!.trim().isNotEmpty) {
      final repo = ref.read(classRepositoryProvider);
      final schoolClass =
          await repo.getClassByName(filters.classFilter!.trim());
      classId = schoolClass?.id;
    }
    return _buildReportRows(db, filters, classId: classId, classIds: classIds);
  },
);

/// Single student report row for the given [studentId] and [filters]. Used by Student Summary modal export.
Future<StudentReportRow?> _buildReportRowForStudent(
  AppDatabase db,
  int studentId,
  ReportFilters filters,
) async {
  final student = await (db.select(db.students)..where((t) => t.id.equals(studentId))).getSingleOrNull();
  if (student == null) return null;
  final startDay = _dateOnly(filters.dateStart);
  final endDayOnly = _dateOnly(filters.dateEnd);
  final endDay = _endOfDay(filters.dateEnd);
  final attendanceRows = await (db.select(db.attendance)
        ..where((t) =>
            t.studentId.equals(studentId) &
            t.date.isBiggerOrEqualValue(startDay) &
            t.date.isSmallerOrEqualValue(endDayOnly),))
      .get();
  final testRows = await (db.select(db.tests)
        ..where((t) =>
            t.studentId.equals(studentId) &
            t.createdAt.isBiggerOrEqualValue(startDay) &
            t.createdAt.isSmallerOrEqualValue(endDay),))
      .get();
  final yearStart = filters.dateStart.year;
  final yearEnd = filters.dateEnd.year;
  final years = <String>{for (var y = yearStart; y <= yearEnd; y++) y.toString()};
  final paymentRows = await (db.select(db.payments)
        ..where((t) => t.studentId.equals(studentId) & t.year.isIn(years)))
      .get();
  final totalPaid = paymentRows.fold<double>(
      0,
      (s, p) =>
          s +
          p.jan +
          p.feb +
          p.mar +
          p.apr +
          p.may +
          p.jun +
          p.jul +
          p.aug +
          p.sep +
          p.oct +
          p.nov +
          p.dec +
          p.lumpSum,);
  const passThreshold = AppConstants.passingTestScore;
  const tuition = AppConstants.fullTuitionAmount;
  final totalDays = attendanceRows.length;
  final presentDays = attendanceRows.where((a) => a.present == 1).length;
  final attPct = totalDays > 0 ? (presentDays / totalDays) * 100 : 0.0;
  final passed = testRows.where((t) => t.score >= passThreshold).length;
  final failed = testRows.where((t) => t.score < passThreshold).length;
  final avg = testRows.isEmpty
      ? 0.0
      : testRows.fold<int>(0, (s, t) => s + t.score) / testRows.length;
  final balance = tuition - totalPaid;
  return StudentReportRow(
    student: student,
    attendanceTotalDays: totalDays,
    attendancePresentDays: presentDays,
    attendancePercentage: attPct,
    testAverage: avg,
    testsPassed: passed,
    testsFailed: failed,
    totalPaid: totalPaid,
    balance: balance,
  );
}

/// Report row for a single student (for Student Summary modal export).
final singleStudentReportRowProvider =
    FutureProvider.autoDispose.family<StudentReportRow?, ({int studentId, ReportFilters filters})>(
  (ref, params) async {
    final db = ref.watch(appDatabaseProvider);
    return _buildReportRowForStudent(db, params.studentId, params.filters);
  },
);

/// Cohort summary rows for report (from dashboard provider).
final cohortReportDataProvider = FutureProvider.autoDispose<List<CohortReportRow>>((ref) async {
  final list = await ref.watch(dashboardCohortSummaryProvider.future);
  return list.map((s) => CohortReportRow(
    year: s.year,
    mode: s.mode,
    studentCount: s.studentCount,
    avgAttendancePercent: s.avgAttendancePercent,
    outstandingTests: s.outstandingTests,
    failedTests: s.failedTests,
    passedTests: s.passedTests,
    totalBalance: s.totalBalance,
  ),).toList();
});

/// All students for report. Scoped by facilitator scope when applicable.
final studentsReportDataProvider = FutureProvider.autoDispose<List<Student>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  var query = db.select(db.students);
  if (scope != null && scope.classIds != null && scope.classIds!.isNotEmpty) {
    query = query..where((t) {
      var p = t.classId.isIn(scope.classIds!);
      if (scope.mode != null && scope.mode!.trim().isNotEmpty) {
        p = p & t.mode.equals(scope.mode!.trim());
      }
      return p;
    });
  }
  return (query
        ..orderBy([
          (t) => OrderingTerm.asc(t.surname),
          (t) => OrderingTerm.asc(t.firstName),
        ]))
      .get();
});

/// Subject row for report: name + class name.
class SubjectReportRow {
  const SubjectReportRow({required this.name, required this.className});
  final String name;
  final String className;
}

/// All subjects with class name for report. Scoped by facilitator scope when applicable.
final subjectsReportDataProvider = FutureProvider.autoDispose<List<SubjectReportRow>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  var query = db.select(db.subjects);
  if (scope != null && scope.classIds != null && scope.classIds!.isNotEmpty) {
    query = query..where((t) => t.classId.isIn(scope.classIds!));
  }
  final subjects = await (query
        ..orderBy([
          (t) => OrderingTerm.asc(t.classId),
          (t) => OrderingTerm.asc(t.name),
        ],))
      .get();
  final classIds = subjects.map((s) => s.classId).toSet().toList();
  final classes = classIds.isEmpty
      ? <int, String>{}
      : {
          for (final c in await (db.select(db.classes)..where((t) => t.id.isIn(classIds))).get())
            c.id: c.name,
        };
  return subjects.map((s) => SubjectReportRow(
    name: s.name,
    className: classes[s.classId] ?? '—',
  ),).toList();
});

/// Attendance row for report (date range filtered).
class AttendanceReportRow {
  const AttendanceReportRow({
    required this.date,
    required this.studentName,
    required this.present,
    this.notes,
  });
  final DateTime date;
  final String studentName;
  final bool present;
  final String? notes;
}

final attendanceReportDataProvider =
    FutureProvider.autoDispose.family<List<AttendanceReportRow>, ReportFilters>((ref, filters) async {
  final db = ref.watch(appDatabaseProvider);
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  final allowedIds = await _allowedStudentIdsForReport(db, scope);
  final startDay = _dateOnly(filters.dateStart);
  final endDayOnly = _dateOnly(filters.dateEnd);
  final rows = await (db.select(db.attendance)
        ..where((t) {
          var p = t.date.isBiggerOrEqualValue(startDay) &
              t.date.isSmallerOrEqualValue(endDayOnly);
          if (allowedIds != null && allowedIds.isNotEmpty) {
            p = p & t.studentId.isIn(allowedIds.toList());
          }
          return p;
        })
        ..orderBy([
          (t) => OrderingTerm.desc(t.date),
          (t) => OrderingTerm.asc(t.studentId),
        ],))
      .get();
  final studentIds = rows.map((r) => r.studentId).toSet().toList();
  final students = studentIds.isEmpty
      ? <int, Student>{}
      : {for (final s in await (db.select(db.students)..where((t) => t.id.isIn(studentIds))).get()) s.id: s};
  return rows.map((r) {
    final s = students[r.studentId];
    return AttendanceReportRow(
      date: r.date,
      studentName: s != null ? '${s.surname}, ${s.firstName}' : '${r.studentId}',
      present: r.present == 1,
      notes: r.notes,
    );
  }).toList();
});

/// Ministry entry row for report.
class MinistryReportRow {
  const MinistryReportRow({
    required this.date,
    required this.studentName,
    required this.ministryType,
    required this.hours,
    required this.approved,
    this.supervisor,
  });
  final DateTime date;
  final String studentName;
  final String ministryType;
  final double hours;
  final bool approved;
  final String? supervisor;
}

final ministryReportDataProvider =
    FutureProvider.autoDispose.family<List<MinistryReportRow>, ReportFilters>((ref, filters) async {
  final db = ref.watch(appDatabaseProvider);
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  final allowedIds = await _allowedStudentIdsForReport(db, scope);
  final startDay = _dateOnly(filters.dateStart);
  final endDay = _endOfDay(filters.dateEnd);
  final rows = await (db.select(db.ministryEntries)
        ..where((t) {
          var p = t.date.isBiggerOrEqualValue(startDay) &
              t.date.isSmallerOrEqualValue(endDay);
          if (allowedIds != null && allowedIds.isNotEmpty) {
            p = p & t.studentId.isIn(allowedIds.toList());
          }
          return p;
        })
        ..orderBy([
          (t) => OrderingTerm.desc(t.date),
        ],))
      .get();
  final studentIds = rows.map((r) => r.studentId).toSet().toList();
  final students = studentIds.isEmpty
      ? <int, Student>{}
      : {for (final s in await (db.select(db.students)..where((t) => t.id.isIn(studentIds))).get()) s.id: s};
  return rows.map((r) {
    final s = students[r.studentId];
    return MinistryReportRow(
      date: r.date,
      studentName: s != null ? '${s.surname}, ${s.firstName}' : '${r.studentId}',
      ministryType: r.ministryType,
      hours: r.hours,
      approved: r.approved,
      supervisor: r.supervisor,
    );
  }).toList();
});

/// Test row for report (with student and subject names).
class TestReportRow {
  const TestReportRow({
    required this.createdAt,
    required this.studentName,
    required this.score,
    this.label,
    this.subjectName,
  });
  final DateTime createdAt;
  final String studentName;
  final int score;
  final String? label;
  final String? subjectName;
}

final testsReportDataProvider =
    FutureProvider.autoDispose.family<List<TestReportRow>, ReportFilters>((ref, filters) async {
  final db = ref.watch(appDatabaseProvider);
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  final allowedIds = await _allowedStudentIdsForReport(db, scope);
  final startDay = _dateOnly(filters.dateStart);
  final endDay = _endOfDay(filters.dateEnd);
  int? sessionId;
  if (filters.academicSession != null && filters.academicSession!.trim().isNotEmpty) {
    final sessionRepo = ref.read(academicSessionRepositoryProvider);
    sessionId = await sessionRepo.getSessionIdByCode(filters.academicSession!.trim());
  }
  final sessionCodeTrim = filters.academicSession?.trim();
  final rows = await (db.select(db.tests)
        ..where((t) {
          var w = t.createdAt.isBiggerOrEqualValue(startDay) &
              t.createdAt.isSmallerOrEqualValue(endDay);
          if (sessionCodeTrim != null && sessionCodeTrim.isNotEmpty) {
            if (sessionId != null) {
              w = w & (t.academicSessionId.equals(sessionId) | t.academicSession.equals(sessionCodeTrim));
            } else {
              w = w & t.academicSession.equals(sessionCodeTrim);
            }
          }
          if (allowedIds != null && allowedIds.isNotEmpty) {
            w = w & t.studentId.isIn(allowedIds.toList());
          }
          return w;
        })
        ..orderBy([
          (t) => OrderingTerm.desc(t.createdAt),
        ],))
      .get();
  final studentIds = rows.map((r) => r.studentId).toSet().toList();
  final subjectIds = rows.map((r) => r.subjectId).whereType<int>().toSet().toList();
  final students = studentIds.isEmpty
      ? <int, Student>{}
      : {for (final s in await (db.select(db.students)..where((t) => t.id.isIn(studentIds))).get()) s.id: s};
  final subjects = subjectIds.isEmpty
      ? <int, String>{}
      : {for (final s in await (db.select(db.subjects)..where((t) => t.id.isIn(subjectIds))).get()) s.id: s.name};
  return rows.map((r) {
    final s = students[r.studentId];
    return TestReportRow(
      createdAt: r.createdAt,
      studentName: s != null ? '${s.surname}, ${s.firstName}' : '${r.studentId}',
      score: r.score,
      label: r.label,
      subjectName: r.subjectId != null ? subjects[r.subjectId] : null,
    );
  }).toList();
});

/// Payment row for report (student name + year + total).
class PaymentReportRow {
  const PaymentReportRow({
    required this.studentName,
    required this.year,
    required this.totalPaid,
  });
  final String studentName;
  final String year;
  final double totalPaid;
}

final paymentsReportDataProvider =
    FutureProvider.autoDispose.family<List<PaymentReportRow>, ReportFilters>((ref, filters) async {
  final db = ref.watch(appDatabaseProvider);
  List<Payment> rows;
  if (filters.academicSession != null && filters.academicSession!.trim().isNotEmpty) {
    final sessionRepo = ref.read(academicSessionRepositoryProvider);
    final sessionId = await sessionRepo.getSessionIdByCode(filters.academicSession!.trim());
    final yearFallback = AcademicSessionRepository.yearFromSessionCode(filters.academicSession!);
    if (sessionId != null) {
      rows = await (db.select(db.payments)
            ..where((t) =>
                t.academicSessionId.equals(sessionId) |
                (t.academicSessionId.isNull() & t.year.equals(yearFallback ?? filters.academicSession!.split('-').first)),))
          .get();
    } else {
      final y = yearFallback ?? filters.dateStart.year.toString();
      rows = await (db.select(db.payments)..where((t) => t.year.equals(y))).get();
    }
  } else {
    final yearStart = filters.dateStart.year;
    final yearEnd = filters.dateEnd.year;
    final years = <String>{for (var y = yearStart; y <= yearEnd; y++) y.toString()};
    rows = await (db.select(db.payments)..where((t) => t.year.isIn(years))).get();
  }
  final studentIds = rows.map((r) => r.studentId).toSet().toList();
  final students = studentIds.isEmpty
      ? <int, Student>{}
      : {for (final s in await (db.select(db.students)..where((t) => t.id.isIn(studentIds))).get()) s.id: s};
  return rows.map((r) {
    final total = r.jan + r.feb + r.mar + r.apr + r.may + r.jun +
        r.jul + r.aug + r.sep + r.oct + r.nov + r.dec + r.lumpSum;
    final s = students[r.studentId];
    return PaymentReportRow(
      studentName: s != null ? '${s.surname}, ${s.firstName}' : '${r.studentId}',
      year: r.year,
      totalPaid: total,
    );
  }).toList();
});

/// Mission payment row for report.
class MissionPaymentReportRow {
  const MissionPaymentReportRow({
    required this.paymentDate,
    required this.studentName,
    required this.amount,
  });
  final DateTime paymentDate;
  final String studentName;
  final double amount;
}

final missionPaymentsReportDataProvider = FutureProvider.autoDispose<List<MissionPaymentReportRow>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final payments = await (db.select(db.missionPayments)
        ..orderBy([(t) => OrderingTerm.desc(t.paymentDate)]))
      .get();
  final partIds = payments.map((r) => r.missionParticipationId).toSet().toList();
  final participations = partIds.isEmpty ? <int, MissionParticipation>{}
      : {for (final p in await (db.select(db.missionParticipations)..where((t) => t.id.isIn(partIds))).get()) p.id: p};
  final studentIds = participations.values.map((p) => p.studentId).toSet().toList();
  final students = studentIds.isEmpty ? <int, Student>{}
      : {for (final s in await (db.select(db.students)..where((t) => t.id.isIn(studentIds))).get()) s.id: s};
  return payments.map((r) {
    final p = participations[r.missionParticipationId];
    final studentId = p?.studentId;
    final s = studentId != null ? students[studentId] : null;
    return MissionPaymentReportRow(
      paymentDate: r.paymentDate,
      studentName: s != null ? '${s.surname}, ${s.firstName}' : '${studentId ?? r.missionParticipationId}',
      amount: r.amount,
    );
  }).toList();
});

/// Mission location row for report.
class MissionLocationReportRow {
  const MissionLocationReportRow({
    required this.name,
    this.description,
    required this.isActive,
  });
  final String name;
  final String? description;
  final bool isActive;
}

final missionLocationsReportDataProvider = FutureProvider.autoDispose<List<MissionLocationReportRow>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await (db.select(db.missionLocations)
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();
  return rows.map((r) => MissionLocationReportRow(
    name: r.name,
    description: r.description,
    isActive: r.isActive,
  ),).toList();
});
