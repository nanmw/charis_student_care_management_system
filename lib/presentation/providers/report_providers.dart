import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/academic_session_repository.dart';
import 'package:charis_student_care/data/repositories/class_repository.dart';
import 'package:charis_student_care/domain/attendance/attendance_thresholds.dart';
import 'package:charis_student_care/domain/finance/session_payment_math.dart';
import 'package:charis_student_care/presentation/providers/academic_session_providers.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/dashboard_providers.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/repository_providers.dart';
import 'package:charis_student_care/presentation/providers/settings_providers.dart';

/// Report type for the Export & Reports screen.
enum ReportType {
  studentSummary('Student Summary', 'student-summary'),
  cohortSummary('Dashboard – Cohort Summary', 'cohort-summary'),
  students('Students', 'students'),
  subjects('Subjects', 'subjects'),
  attendance('Attendance', 'attendance'),
  ministryHours('Ministry Hours', 'ministry-hours'),
  tests('Tests', 'tests'),
  payments('Finances', 'payments'),
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
    required this.balanceDueExpectedMonthly,
  });
  final String year;
  final String mode;
  final int studentCount;
  final double? avgAttendancePercent;
  final int outstandingTests;
  final int failedTests;
  final int passedTests;

  /// Balance due as expected for the selected month (same semantics as dashboard column).
  final double balanceDueExpectedMonthly;
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
    this.studentStatusScope = StudentStatusScope.activeOnly,
  });

  final String mode;
  final DateTime dateStart;
  final DateTime dateEnd;

  /// Optional year filter for students (e.g. admission year). When set, only students
  /// with this admission year are included. When null, all students matching mode are included.
  final String? year;

  /// Optional academic session code (e.g. 2026). When set, session-based reports
  /// (payments, tests) filter by this session instead of raw year.
  final String? academicSession;

  /// Optional class filter (e.g. "Year 1", "Year 2", "Year 3"). When set, only students
  /// in that class are included. When null, year filter is used if set.
  final String? classFilter;

  /// Student status scope for student-linked exports.
  final StudentStatusScope studentStatusScope;

  bool get activeOnly => studentStatusScope == StudentStatusScope.activeOnly;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ReportFilters &&
        other.mode == mode &&
        other.dateStart == dateStart &&
        other.dateEnd == dateEnd &&
        other.year == year &&
        other.academicSession == academicSession &&
        other.classFilter == classFilter &&
        other.studentStatusScope == studentStatusScope;
  }

  @override
  int get hashCode => Object.hash(
        mode,
        dateStart,
        dateEnd,
        year,
        academicSession,
        classFilter,
        studentStatusScope,
      );
}

/// Student scope for reports.
enum StudentStatusScope { activeOnly, all }

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
    this.attendanceExpectedDays = 0,
    this.attendanceThresholdMet = true,
    this.attendanceShortfall = 0,
  });

  final Student student;
  final int attendanceTotalDays;
  final int attendancePresentDays;
  final double attendancePercentage;
  final int attendanceExpectedDays;
  final bool attendanceThresholdMet;
  final int attendanceShortfall;
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

/// Pick threshold period from filter span: ~month / ~term / year.
AttendanceThresholdPeriod _thresholdPeriodForFilters(ReportFilters filters) {
  final days =
      _dateOnly(filters.dateEnd).difference(_dateOnly(filters.dateStart)).inDays;
  if (days <= 35) return AttendanceThresholdPeriod.month;
  if (days <= 100) return AttendanceThresholdPeriod.term;
  return AttendanceThresholdPeriod.year;
}

AttendanceThresholdResult _thresholdForPresentDays(
  ReportFilters filters,
  int presentDays,
  AttendanceThresholdConfig config,
) {
  return evaluateAttendanceThreshold(
    period: _thresholdPeriodForFilters(filters),
    presentDays: presentDays,
    config: config,
  );
}

/// Sentinel for Export Class dropdown: no class restriction beyond facilitator scope.
const kReportClassFilterAll = 'All';

bool _isAllClassFilter(String? classFilter) {
  if (classFilter == null || classFilter.trim().isEmpty) return true;
  return classFilter.trim().toLowerCase() ==
      kReportClassFilterAll.toLowerCase();
}

/// Returns student ids allowed for a report.
/// Empty set = deny-all (facilitator with no classes, or filters match nobody).
/// Null = no student id filter (should not happen when [filters] is provided for admin).
Future<Set<int>?> _allowedStudentIdsForReport(
  AppDatabase db,
  FacilitatorScope? scope, {
  ReportFilters? filters,
  int? resolvedClassId,
}) async {
  if (scope != null) {
    if (scope.classIds == null || scope.classIds!.isEmpty) {
      return <int>{};
    }
    List<int> classIds = List<int>.from(scope.classIds!);
    if (resolvedClassId != null) {
      if (!classIds.contains(resolvedClassId)) {
        return <int>{};
      }
      classIds = [resolvedClassId];
    }
    final students = await (db.select(db.students)
          ..where((t) {
            var p = t.classId.isIn(classIds);
            if (scope.mode != null && scope.mode!.trim().isNotEmpty) {
              p = p & t.mode.equals(scope.mode!.trim());
            } else if (filters != null && filters.mode.trim().isNotEmpty) {
              p = p & t.mode.equals(filters.mode.trim());
            }
            if (filters != null && filters.activeOnly) {
              p = p & t.status.equals('Active');
            }
            return p;
          }))
        .get();
    return students.map((s) => s.id).toSet();
  }

  if (filters == null) return null;

  final students = await (db.select(db.students)
        ..where((t) {
          var p = t.mode.equals(filters.mode);
          if (filters.activeOnly) {
            p = p & t.status.equals('Active');
          }
          if (resolvedClassId != null) {
            p = p & t.classId.equals(resolvedClassId);
          }
          return p;
        }))
      .get();
  return students.map((s) => s.id).toSet();
}

Future<int?> _resolveClassFilterId(Ref ref, ReportFilters filters) async {
  if (_isAllClassFilter(filters.classFilter)) {
    return null;
  }
  final schoolClass = await ref
      .read(classRepositoryProvider)
      .getClassByName(filters.classFilter!.trim());
  return schoolClass?.id;
}

/// True when [filters] names a specific class that does not exist in the DB.
Future<bool> reportClassFilterIsUnresolved(
  ClassRepository classRepo,
  ReportFilters filters,
) async {
  if (_isAllClassFilter(filters.classFilter)) return false;
  final schoolClass =
      await classRepo.getClassByName(filters.classFilter!.trim());
  return schoolClass == null;
}

/// True when [filters] names a session that does not exist in the DB.
Future<bool> reportSessionFilterIsUnresolved(
  AcademicSessionRepository sessionRepo,
  ReportFilters filters,
) async {
  final code = filters.academicSession?.trim();
  if (code == null || code.isEmpty) return false;
  final id = await sessionRepo.getSessionIdByCode(code);
  return id == null;
}

/// Effective class id(s) after intersecting facilitator scope with the Class filter.
/// Returns empty list when the selection is outside scope (deny-all).
/// Returns null when there is no class restriction (admin + All).
Future<({int? classId, List<int>? classIds, bool denyAll})>
    _resolveEffectiveClassSelection(
  FacilitatorScope? scope,
  int? resolvedClassId,
) async {
  if (scope != null) {
    if (scope.classIds == null || scope.classIds!.isEmpty) {
      return (classId: null, classIds: null, denyAll: true);
    }
    if (resolvedClassId != null) {
      if (!scope.classIds!.contains(resolvedClassId)) {
        return (classId: null, classIds: null, denyAll: true);
      }
      return (classId: resolvedClassId, classIds: null, denyAll: false);
    }
    return (classId: null, classIds: scope.classIds, denyAll: false);
  }
  if (resolvedClassId != null) {
    return (classId: resolvedClassId, classIds: null, denyAll: false);
  }
  return (classId: null, classIds: null, denyAll: false);
}

Future<int?> _sessionIdForFilters(Ref ref, ReportFilters filters) async {
  final code = filters.academicSession?.trim();
  if (code == null || code.isEmpty) return null;
  return ref.read(academicSessionRepositoryProvider).getSessionIdByCode(code);
}

/// Match the selected session, or legacy rows that were never stamped.
Expression<bool> _academicSessionIdMatchesOrUnscoped(
  GeneratedColumn<int> column,
  int sessionId,
) {
  return column.equals(sessionId) | column.isNull();
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
  required double sessionTuition,
  AttendanceThresholdsByMode attendanceThresholds =
      AttendanceThresholdsByMode.defaults,
}) async {
  final studentsQuery = db.select(db.students)
    ..where((t) {
      var p = t.mode.equals(filters.mode);
      if (filters.activeOnly) {
        p = p & t.status.equals('Active');
      }
      if (classIds != null && classIds.isNotEmpty) {
        p = p & t.classId.isIn(classIds);
      } else if (classId != null) {
        p = p & t.classId.equals(classId);
      } else if (filters.year != null && filters.year!.trim().isNotEmpty) {
        p = p & t.admissionYear.equals(filters.year!.trim());
      }
      return p;
    })
    ..orderBy([
      (t) => OrderingTerm.asc(t.surname),
      (t) => OrderingTerm.asc(t.firstName),
    ]);
  final studentList = await studentsQuery.get();
  if (studentList.isEmpty) return [];

  final studentIds = studentList.map((s) => s.id).toList();
  final startDay = _dateOnly(filters.dateStart);
  final endDay = _endOfDay(filters.dateEnd);

  int? sessionId;
  final sessionCodeTrim = filters.academicSession?.trim();
  if (sessionCodeTrim != null && sessionCodeTrim.isNotEmpty) {
    final result = await db.customSelect(
      'SELECT id FROM academic_sessions WHERE code = ? LIMIT 1',
      variables: [Variable.withString(sessionCodeTrim)],
      readsFrom: {db.academicSessions},
    ).getSingleOrNull();
    sessionId = result?.data['id'] as int?;
  }

  // Attendance in range; when session resolves, align with Attendance report.
  final attendanceRows = await (db.select(db.attendance)
        ..where((t) {
          var p = t.studentId.isIn(studentIds) &
              t.date.isBiggerOrEqualValue(startDay) &
              t.date.isSmallerOrEqualValue(endDay);
          if (sessionCodeTrim != null &&
              sessionCodeTrim.isNotEmpty &&
              sessionId != null) {
            p = p & _academicSessionIdMatchesOrUnscoped(
              t.academicSessionId,
              sessionId,
            );
          }
          return p;
        }))
      .get();

  final attendanceByStudent = <int, List<AttendanceData>>{};
  for (final a in attendanceRows) {
    attendanceByStudent.putIfAbsent(a.studentId, () => []).add(a);
  }

  final testRows = await (db.select(db.tests)
        ..where((t) {
          var p = t.studentId.isIn(studentIds) &
              t.createdAt.isBiggerOrEqualValue(startDay) &
              t.createdAt.isSmallerOrEqualValue(endDay);
          if (sessionCodeTrim != null && sessionCodeTrim.isNotEmpty) {
            if (sessionId != null) {
              p = p &
                  (t.academicSessionId.equals(sessionId) |
                      t.academicSession.equals(sessionCodeTrim));
            } else {
              p = p & t.academicSession.equals(sessionCodeTrim);
            }
          }
          return p;
        }))
      .get();

  final testsByStudent = <int, List<Test>>{};
  for (final t in testRows) {
    testsByStudent.putIfAbsent(t.studentId, () => []).add(t);
  }

  // Payments: years overlapping the date range
  final List<Payment> paymentRows;
  if (sessionCodeTrim != null && sessionCodeTrim.isNotEmpty) {
    final yearFallback =
        AcademicSessionRepository.yearFromSessionCode(sessionCodeTrim);
    if (sessionId != null) {
      paymentRows = await (db.select(db.payments)
            ..where(
              (t) =>
                  t.studentId.isIn(studentIds) &
                  (t.academicSessionId.equals(sessionId!) |
                      (t.academicSessionId.isNull() &
                          t.year.equals(
                            yearFallback ?? sessionCodeTrim.split('-').first,
                          ))),
            ))
          .get();
    } else {
      final yearOnly = yearFallback ?? filters.dateStart.year.toString();
      paymentRows = await (db.select(db.payments)
            ..where(
              (t) => t.studentId.isIn(studentIds) & t.year.equals(yearOnly),
            ))
          .get();
    }
  } else {
    final yearStart = filters.dateStart.year;
    final yearEnd = filters.dateEnd.year;
    final years = <String>{
      for (var y = yearStart; y <= yearEnd; y++) y.toString(),
    };
    paymentRows = await (db.select(db.payments)
          ..where((t) => t.studentId.isIn(studentIds) & t.year.isIn(years)))
        .get();
  }

  final paymentByStudent = <int, double>{};
  for (final p in paymentRows) {
    final total = paymentTotalInDateRange(p, filters.dateStart, filters.dateEnd);
    paymentByStudent[p.studentId] =
        (paymentByStudent[p.studentId] ?? 0.0) + total;
  }

  const passThreshold = AppConstants.passingTestScore;

  final rows = <StudentReportRow>[];
  for (final student in studentList) {
    final attList = attendanceByStudent[student.id] ?? [];
    final tList = testsByStudent[student.id] ?? [];
    final paid = paymentByStudent[student.id] ?? 0.0;

    // Omit students with no in-range activity (date/session).
    if (attList.isEmpty && tList.isEmpty && paid == 0.0) {
      continue;
    }

    final totalDays = attList.length;
    final presentDays = attList.where((a) => a.present == 1).length;
    final attPct = totalDays > 0 ? (presentDays / totalDays) * 100 : 0.0;

    final passed = tList.where((t) => t.score >= passThreshold).length;
    final failed = tList.where((t) => t.score < passThreshold).length;
    final avg = tList.isEmpty
        ? 0.0
        : tList.fold<int>(0, (s, t) => s + t.score) / tList.length;

    final balance = sessionTuition - paid;

    final threshold = _thresholdForPresentDays(
      filters,
      presentDays,
      attendanceThresholds.forMode(student.mode),
    );

    rows.add(
      StudentReportRow(
        student: student,
        attendanceTotalDays: totalDays,
        attendancePresentDays: presentDays,
        attendancePercentage: attPct,
        attendanceExpectedDays: threshold.expectedDays,
        attendanceThresholdMet: threshold.met,
        attendanceShortfall: threshold.shortfall,
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
    final sessionTuition = ref.watch(sessionTuitionAmountProvider);
    final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
    final resolvedClassId = await _resolveClassFilterId(ref, filters);
    final selection =
        await _resolveEffectiveClassSelection(scope, resolvedClassId);
    if (selection.denyAll) return [];
    final thresholds = await ref.watch(attendanceThresholdsByModeProvider.future);
    return _buildReportRows(
      db,
      filters,
      classId: selection.classId,
      classIds: selection.classIds,
      sessionTuition: sessionTuition,
      attendanceThresholds: thresholds,
    );
  },
);

/// Single student report row for the given [studentId] and [filters]. Used by Student Summary modal export.
Future<StudentReportRow?> _buildReportRowForStudent(
  AppDatabase db,
  int studentId,
  ReportFilters filters,
  double sessionTuition, {
  AttendanceThresholdsByMode attendanceThresholds =
      AttendanceThresholdsByMode.defaults,
}) async {
  final student = await (db.select(db.students)
        ..where((t) => t.id.equals(studentId)))
      .getSingleOrNull();
  if (student == null) return null;
  final startDay = _dateOnly(filters.dateStart);
  final endDay = _endOfDay(filters.dateEnd);
  int? sessionId;
  final sessionCodeTrim = filters.academicSession?.trim();
  if (sessionCodeTrim != null && sessionCodeTrim.isNotEmpty) {
    final result = await db.customSelect(
      'SELECT id FROM academic_sessions WHERE code = ? LIMIT 1',
      variables: [Variable.withString(sessionCodeTrim)],
      readsFrom: {db.academicSessions},
    ).getSingleOrNull();
    sessionId = result?.data['id'] as int?;
  }
  final attendanceRows = await (db.select(db.attendance)
        ..where((t) {
          var p = t.studentId.equals(studentId) &
              t.date.isBiggerOrEqualValue(startDay) &
              t.date.isSmallerOrEqualValue(endDay);
          if (sessionCodeTrim != null &&
              sessionCodeTrim.isNotEmpty &&
              sessionId != null) {
            p = p & _academicSessionIdMatchesOrUnscoped(
              t.academicSessionId,
              sessionId,
            );
          }
          return p;
        }))
      .get();
  final testRows = await (db.select(db.tests)
        ..where((t) {
          var p = t.studentId.equals(studentId) &
              t.createdAt.isBiggerOrEqualValue(startDay) &
              t.createdAt.isSmallerOrEqualValue(endDay);
          if (sessionCodeTrim != null && sessionCodeTrim.isNotEmpty) {
            if (sessionId != null) {
              p = p &
                  (t.academicSessionId.equals(sessionId) |
                      t.academicSession.equals(sessionCodeTrim));
            } else {
              p = p & t.academicSession.equals(sessionCodeTrim);
            }
          }
          return p;
        }))
      .get();
  final List<Payment> paymentRows;
  if (sessionCodeTrim != null && sessionCodeTrim.isNotEmpty) {
    final yearFallback =
        AcademicSessionRepository.yearFromSessionCode(sessionCodeTrim);
    if (sessionId != null) {
      paymentRows = await (db.select(db.payments)
            ..where(
              (t) =>
                  t.studentId.equals(studentId) &
                  (t.academicSessionId.equals(sessionId!) |
                      (t.academicSessionId.isNull() &
                          t.year.equals(
                            yearFallback ?? sessionCodeTrim.split('-').first,
                          ))),
            ))
          .get();
    } else {
      final y = yearFallback ?? filters.dateStart.year.toString();
      paymentRows = await (db.select(db.payments)
            ..where((t) => t.studentId.equals(studentId) & t.year.equals(y)))
          .get();
    }
  } else {
    final yearStart = filters.dateStart.year;
    final yearEnd = filters.dateEnd.year;
    final years = <String>{
      for (var y = yearStart; y <= yearEnd; y++) y.toString(),
    };
    paymentRows = await (db.select(db.payments)
          ..where((t) => t.studentId.equals(studentId) & t.year.isIn(years)))
        .get();
  }
  final totalPaid = paymentRows.fold<double>(
    0,
    (s, p) => s + paymentTotalInDateRange(p, filters.dateStart, filters.dateEnd),
  );
  const passThreshold = AppConstants.passingTestScore;
  final totalDays = attendanceRows.length;
  final presentDays = attendanceRows.where((a) => a.present == 1).length;
  final attPct = totalDays > 0 ? (presentDays / totalDays) * 100 : 0.0;
  final passed = testRows.where((t) => t.score >= passThreshold).length;
  final failed = testRows.where((t) => t.score < passThreshold).length;
  final avg = testRows.isEmpty
      ? 0.0
      : testRows.fold<int>(0, (s, t) => s + t.score) / testRows.length;
  final balance = sessionTuition - totalPaid;
  final threshold = _thresholdForPresentDays(
    filters,
    presentDays,
    attendanceThresholds.forMode(student.mode),
  );
  return StudentReportRow(
    student: student,
    attendanceTotalDays: totalDays,
    attendancePresentDays: presentDays,
    attendancePercentage: attPct,
    attendanceExpectedDays: threshold.expectedDays,
    attendanceThresholdMet: threshold.met,
    attendanceShortfall: threshold.shortfall,
    testAverage: avg,
    testsPassed: passed,
    testsFailed: failed,
    totalPaid: totalPaid,
    balance: balance,
  );
}

/// Report row for a single student (for Student Summary modal export).
final singleStudentReportRowProvider = FutureProvider.autoDispose
    .family<StudentReportRow?, ({int studentId, ReportFilters filters})>(
  (ref, params) async {
    final db = ref.watch(appDatabaseProvider);
    final sessionTuition = ref.watch(sessionTuitionAmountProvider);
    final thresholds = await ref.watch(attendanceThresholdsByModeProvider.future);
    return _buildReportRowForStudent(
      db,
      params.studentId,
      params.filters,
      sessionTuition,
      attendanceThresholds: thresholds,
    );
  },
);

/// Cohort summary rows for report (from dashboard provider).
final cohortReportDataProvider =
    FutureProvider.autoDispose<List<CohortReportRow>>((ref) async {
  final list = await ref.watch(dashboardCohortSummaryProvider.future);
  return list
      .map(
        (s) => CohortReportRow(
          year: s.year,
          mode: s.mode,
          studentCount: s.studentCount,
          avgAttendancePercent: s.avgAttendancePercent,
          outstandingTests: s.outstandingTests,
          failedTests: s.failedTests,
          passedTests: s.passedTests,
          balanceDueExpectedMonthly: s.balanceDueExpectedMonthly,
        ),
      )
      .toList();
});

/// All students for report. Scoped by facilitator scope when applicable.
class StudentsReportRow {
  const StudentsReportRow({
    required this.student,
    required this.className,
  });

  final Student student;
  final String className;
}

final studentsReportDataProvider = FutureProvider.autoDispose
    .family<List<StudentsReportRow>, ReportFilters>((ref, filters) async {
  final db = ref.watch(appDatabaseProvider);
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  final resolvedClassId = await _resolveClassFilterId(ref, filters);
  final selection =
      await _resolveEffectiveClassSelection(scope, resolvedClassId);
  if (selection.denyAll) return [];

  var query = db.select(db.students);
  query = query
    ..where((t) {
      var p = t.id.isNotNull();
      if (filters.activeOnly) {
        p = p & t.status.equals('Active');
      }
      if (scope != null &&
          scope.mode != null &&
          scope.mode!.trim().isNotEmpty) {
        p = p & t.mode.equals(scope.mode!.trim());
      } else if (filters.mode.trim().isNotEmpty) {
        p = p & t.mode.equals(filters.mode.trim());
      }
      if (selection.classIds != null && selection.classIds!.isNotEmpty) {
        p = p & t.classId.isIn(selection.classIds!);
      } else if (selection.classId != null) {
        p = p & t.classId.equals(selection.classId!);
      }
      return p;
    });

  final students = await (query
        ..orderBy([
          (t) => OrderingTerm.asc(t.surname),
          (t) => OrderingTerm.asc(t.firstName),
        ]))
      .get();
  final classIds =
      students.map((s) => s.classId).whereType<int>().toSet().toList();
  final classes = classIds.isEmpty
      ? <int, String>{}
      : {
          for (final c in await (db.select(db.classes)
                ..where((t) => t.id.isIn(classIds)))
              .get())
            c.id: c.name,
        };
  return students
      .map(
        (s) => StudentsReportRow(
          student: s,
          className: s.classId != null ? (classes[s.classId!] ?? '—') : '—',
        ),
      )
      .toList();
});

/// Subject row for report: name + class name.
class SubjectReportRow {
  const SubjectReportRow({required this.name, required this.className});
  final String name;
  final String className;
}

/// All subjects with class name for report. Scoped by facilitator scope when applicable.
final subjectsReportDataProvider =
    FutureProvider.autoDispose.family<List<SubjectReportRow>, ReportFilters>(
        (ref, filters) async {
  final db = ref.watch(appDatabaseProvider);
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  final resolvedClassId = await _resolveClassFilterId(ref, filters);
  final selection =
      await _resolveEffectiveClassSelection(scope, resolvedClassId);
  if (selection.denyAll) return [];

  List<int>? restrictToClassIds;
  if (selection.classIds != null && selection.classIds!.isNotEmpty) {
    restrictToClassIds = List<int>.from(selection.classIds!);
  } else if (selection.classId != null) {
    restrictToClassIds = [selection.classId!];
  }

  // Mode: further restrict to classes that have matching students.
  final scopeMode = scope?.mode?.trim();
  if (filters.mode.trim().isNotEmpty ||
      (scopeMode != null && scopeMode.isNotEmpty)) {
    final mode = (scopeMode != null && scopeMode.isNotEmpty)
        ? scopeMode
        : filters.mode.trim();
    final modeStudents = await (db.select(db.students)
          ..where((t) {
            var p = t.mode.equals(mode);
            if (filters.activeOnly) {
              p = p & t.status.equals('Active');
            }
            if (restrictToClassIds != null && restrictToClassIds.isNotEmpty) {
              p = p & t.classId.isIn(restrictToClassIds);
            }
            return p;
          }))
        .get();
    final classIdsFromStudents =
        modeStudents.map((s) => s.classId).whereType<int>().toSet();
    if (classIdsFromStudents.isEmpty) {
      if (resolvedClassId != null) {
        restrictToClassIds = [resolvedClassId];
      } else {
        return [];
      }
    } else {
      restrictToClassIds = classIdsFromStudents.toList();
    }
  }

  var query = db.select(db.subjects);
  if (restrictToClassIds != null && restrictToClassIds.isNotEmpty) {
    query = query..where((t) => t.classId.isIn(restrictToClassIds!));
  }
  final subjects = await (query
        ..orderBy(
          [
            (t) => OrderingTerm.asc(t.classId),
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ],
        ))
      .get();
  final classIds = subjects.map((s) => s.classId).toSet().toList();
  final classes = classIds.isEmpty
      ? <int, String>{}
      : {
          for (final c in await (db.select(db.classes)
                ..where((t) => t.id.isIn(classIds)))
              .get())
            c.id: c.name,
        };
  return subjects
      .map(
        (s) => SubjectReportRow(
          name: s.name,
          className: classes[s.classId] ?? '—',
        ),
      )
      .toList();
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

final attendanceReportDataProvider = FutureProvider.autoDispose
    .family<List<AttendanceReportRow>, ReportFilters>((ref, filters) async {
  final db = ref.watch(appDatabaseProvider);
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  final resolvedClassId = await _resolveClassFilterId(ref, filters);
  final allowedIds = await _allowedStudentIdsForReport(
    db,
    scope,
    filters: filters,
    resolvedClassId: resolvedClassId,
  );
  final startDay = _dateOnly(filters.dateStart);
  final endDay = _endOfDay(filters.dateEnd);
  final sessionId = await _sessionIdForFilters(ref, filters);
  final sessionCodeTrim = filters.academicSession?.trim();
  final rows = await (db.select(db.attendance)
        ..where((t) {
          var p = t.date.isBiggerOrEqualValue(startDay) &
              t.date.isSmallerOrEqualValue(endDay);
          if (sessionCodeTrim != null &&
              sessionCodeTrim.isNotEmpty &&
              sessionId != null) {
            p = p & _academicSessionIdMatchesOrUnscoped(
              t.academicSessionId,
              sessionId,
            );
          }
          if (allowedIds != null) {
            if (allowedIds.isEmpty) {
              p = p & t.studentId.equals(-1);
            } else {
              p = p & t.studentId.isIn(allowedIds.toList());
            }
          }
          return p;
        })
        ..orderBy(
          [
            (t) => OrderingTerm.desc(t.date),
            (t) => OrderingTerm.asc(t.studentId),
          ],
        ))
      .get();
  final studentIds = rows.map((r) => r.studentId).toSet().toList();
  var students = studentIds.isEmpty
      ? <int, Student>{}
      : {
          for (final s in await (db.select(db.students)
                ..where((t) => t.id.isIn(studentIds)))
              .get())
            s.id: s,
        };
  if (filters.activeOnly) {
    students = {
      for (final entry in students.entries)
        if (entry.value.status == 'Active') entry.key: entry.value,
    };
  }
  return rows
      .map((r) {
        final s = students[r.studentId];
        if (filters.activeOnly && s == null) return null;
        return AttendanceReportRow(
          date: r.date,
          studentName:
              s != null ? '${s.surname}, ${s.firstName}' : '${r.studentId}',
          present: r.present == 1,
          notes: r.notes,
        );
      })
      .whereType<AttendanceReportRow>()
      .toList();
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

final ministryReportDataProvider = FutureProvider.autoDispose
    .family<List<MinistryReportRow>, ReportFilters>((ref, filters) async {
  final db = ref.watch(appDatabaseProvider);
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  final resolvedClassId = await _resolveClassFilterId(ref, filters);
  final allowedIds = await _allowedStudentIdsForReport(
    db,
    scope,
    filters: filters,
    resolvedClassId: resolvedClassId,
  );
  final startDay = _dateOnly(filters.dateStart);
  final endDay = _endOfDay(filters.dateEnd);
  final sessionId = await _sessionIdForFilters(ref, filters);
  final sessionCodeTrim = filters.academicSession?.trim();
  final rows = await (db.select(db.ministryEntries)
        ..where((t) {
          var p = t.date.isBiggerOrEqualValue(startDay) &
              t.date.isSmallerOrEqualValue(endDay);
          if (sessionCodeTrim != null &&
              sessionCodeTrim.isNotEmpty &&
              sessionId != null) {
            p = p & _academicSessionIdMatchesOrUnscoped(
              t.academicSessionId,
              sessionId,
            );
          }
          if (allowedIds != null) {
            if (allowedIds.isEmpty) {
              p = p & t.studentId.equals(-1);
            } else {
              p = p & t.studentId.isIn(allowedIds.toList());
            }
          }
          return p;
        })
        ..orderBy(
          [
            (t) => OrderingTerm.desc(t.date),
          ],
        ))
      .get();
  final studentIds = rows.map((r) => r.studentId).toSet().toList();
  var students = studentIds.isEmpty
      ? <int, Student>{}
      : {
          for (final s in await (db.select(db.students)
                ..where((t) => t.id.isIn(studentIds)))
              .get())
            s.id: s,
        };
  if (filters.activeOnly) {
    students = {
      for (final entry in students.entries)
        if (entry.value.status == 'Active') entry.key: entry.value,
    };
  }
  return rows
      .map((r) {
        final s = students[r.studentId];
        if (filters.activeOnly && s == null) return null;
        return MinistryReportRow(
          date: r.date,
          studentName:
              s != null ? '${s.surname}, ${s.firstName}' : '${r.studentId}',
          ministryType: r.ministryType,
          hours: r.hours,
          approved: r.approved,
          supervisor: r.supervisor,
        );
      })
      .whereType<MinistryReportRow>()
      .toList();
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

final testsReportDataProvider = FutureProvider.autoDispose
    .family<List<TestReportRow>, ReportFilters>((ref, filters) async {
  final db = ref.watch(appDatabaseProvider);
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  final resolvedClassId = await _resolveClassFilterId(ref, filters);
  final allowedIds = await _allowedStudentIdsForReport(
    db,
    scope,
    filters: filters,
    resolvedClassId: resolvedClassId,
  );
  final startDay = _dateOnly(filters.dateStart);
  final endDay = _endOfDay(filters.dateEnd);
  final sessionId = await _sessionIdForFilters(ref, filters);
  final sessionCodeTrim = filters.academicSession?.trim();
  final rows = await (db.select(db.tests)
        ..where((t) {
          var w = t.createdAt.isBiggerOrEqualValue(startDay) &
              t.createdAt.isSmallerOrEqualValue(endDay);
          if (sessionCodeTrim != null && sessionCodeTrim.isNotEmpty) {
            if (sessionId != null) {
              w = w &
                  (t.academicSessionId.equals(sessionId) |
                      t.academicSession.equals(sessionCodeTrim));
            } else {
              w = w & t.academicSession.equals(sessionCodeTrim);
            }
          }
          if (allowedIds != null) {
            if (allowedIds.isEmpty) {
              w = w & t.studentId.equals(-1);
            } else {
              w = w & t.studentId.isIn(allowedIds.toList());
            }
          }
          return w;
        })
        ..orderBy(
          [
            (t) => OrderingTerm.desc(t.createdAt),
          ],
        ))
      .get();
  final studentIds = rows.map((r) => r.studentId).toSet().toList();
  final subjectIds =
      rows.map((r) => r.subjectId).whereType<int>().toSet().toList();
  var students = studentIds.isEmpty
      ? <int, Student>{}
      : {
          for (final s in await (db.select(db.students)
                ..where((t) => t.id.isIn(studentIds)))
              .get())
            s.id: s,
        };
  if (filters.activeOnly) {
    students = {
      for (final entry in students.entries)
        if (entry.value.status == 'Active') entry.key: entry.value,
    };
  }
  final subjects = subjectIds.isEmpty
      ? <int, String>{}
      : {
          for (final s in await (db.select(db.subjects)
                ..where((t) => t.id.isIn(subjectIds)))
              .get())
            s.id: s.name,
        };
  return rows
      .map((r) {
        final s = students[r.studentId];
        if (filters.activeOnly && s == null) return null;
        return TestReportRow(
          createdAt: r.createdAt,
          studentName:
              s != null ? '${s.surname}, ${s.firstName}' : '${r.studentId}',
          score: r.score,
          label: r.label,
          subjectName: r.subjectId != null ? subjects[r.subjectId] : null,
        );
      })
      .whereType<TestReportRow>()
      .toList();
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

final paymentsReportDataProvider = FutureProvider.autoDispose
    .family<List<PaymentReportRow>, ReportFilters>((ref, filters) async {
  final db = ref.watch(appDatabaseProvider);
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  final resolvedClassId = await _resolveClassFilterId(ref, filters);
  final allowedIds = await _allowedStudentIdsForReport(
    db,
    scope,
    filters: filters,
    resolvedClassId: resolvedClassId,
  );
  List<Payment> rows;
  if (filters.academicSession != null &&
      filters.academicSession!.trim().isNotEmpty) {
    final sessionRepo = ref.read(academicSessionRepositoryProvider);
    final sessionId =
        await sessionRepo.getSessionIdByCode(filters.academicSession!.trim());
    final yearFallback =
        AcademicSessionRepository.yearFromSessionCode(filters.academicSession!);
    if (sessionId != null) {
      rows = await (db.select(db.payments)
            ..where(
              (t) =>
                  t.academicSessionId.equals(sessionId) |
                  (t.academicSessionId.isNull() &
                      t.year.equals(
                        yearFallback ??
                            filters.academicSession!.split('-').first,
                      )),
            ))
          .get();
    } else {
      final y = yearFallback ?? filters.dateStart.year.toString();
      rows =
          await (db.select(db.payments)..where((t) => t.year.equals(y))).get();
    }
  } else {
    final yearStart = filters.dateStart.year;
    final yearEnd = filters.dateEnd.year;
    final years = <String>{
      for (var y = yearStart; y <= yearEnd; y++) y.toString(),
    };
    rows =
        await (db.select(db.payments)..where((t) => t.year.isIn(years))).get();
  }
  if (allowedIds != null) {
    if (allowedIds.isEmpty) {
      rows = [];
    } else {
      rows = rows.where((r) => allowedIds.contains(r.studentId)).toList();
    }
  }
  final studentIds = rows.map((r) => r.studentId).toSet().toList();
  var students = studentIds.isEmpty
      ? <int, Student>{}
      : {
          for (final s in await (db.select(db.students)
                ..where((t) => t.id.isIn(studentIds)))
              .get())
            s.id: s,
        };
  if (filters.activeOnly) {
    students = {
      for (final entry in students.entries)
        if (entry.value.status == 'Active') entry.key: entry.value,
    };
  }
  return rows
      .map((r) {
        final year = int.tryParse(r.year);
        if (year != null &&
            !calendarYearOverlapsRange(
              year,
              filters.dateStart,
              filters.dateEnd,
            )) {
          return null;
        }
        final total = paymentTotalInDateRange(
          r,
          filters.dateStart,
          filters.dateEnd,
        );
        final s = students[r.studentId];
        if (filters.activeOnly && s == null) return null;
        return PaymentReportRow(
          studentName:
              s != null ? '${s.surname}, ${s.firstName}' : '${r.studentId}',
          year: r.year,
          totalPaid: total,
        );
      })
      .whereType<PaymentReportRow>()
      .toList();
});

/// Mission payment schedule row for report (matches Missions Payment grid).
class MissionPaymentReportRow {
  const MissionPaymentReportRow({
    required this.studentName,
    this.tripSelected,
    this.date,
    required this.amount,
    required this.mar,
    required this.apr,
    required this.may,
    required this.jun,
    required this.jul,
    required this.aug,
    required this.sep,
    required this.oct,
    this.comment,
  });
  final String studentName;
  final String? tripSelected;
  final DateTime? date;
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

  double get paidToDate =>
      mar + apr + may + jun + jul + aug + sep + oct;
  double get balance => amount - paidToDate;
}

final missionPaymentsReportDataProvider = FutureProvider.autoDispose
    .family<List<MissionPaymentReportRow>, ReportFilters>((ref, filters) async {
  final db = ref.watch(appDatabaseProvider);
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  final resolvedClassId = await _resolveClassFilterId(ref, filters);
  final allowedIds = await _allowedStudentIdsForReport(
    db,
    scope,
    filters: filters,
    resolvedClassId: resolvedClassId,
  );
  final sessionId = await _sessionIdForFilters(ref, filters);
  final sessionCodeTrim = filters.academicSession?.trim();
  final yearFallback =
      AcademicSessionRepository.yearFromSessionCode(sessionCodeTrim);

  final query = db.select(db.missionPaymentSchedule);
  if (sessionCodeTrim != null && sessionCodeTrim.isNotEmpty) {
    query.where((t) {
      if (sessionId != null && yearFallback != null) {
        return t.academicSessionId.equals(sessionId) |
            (t.academicSessionId.isNull() & t.year.equals(yearFallback));
      }
      if (sessionId != null) {
        return t.academicSessionId.equals(sessionId);
      }
      if (yearFallback != null) {
        return t.year.equals(yearFallback);
      }
      return const CustomExpression<bool>('1');
    });
  }
  query.orderBy([(t) => OrderingTerm.asc(t.studentId)]);
  final schedules = await query.get();

  final studentIds = schedules.map((r) => r.studentId).toSet().toList();
  var students = studentIds.isEmpty
      ? <int, Student>{}
      : {
          for (final s in await (db.select(db.students)
                ..where((t) => t.id.isIn(studentIds)))
              .get())
            s.id: s,
        };
  if (filters.activeOnly) {
    students = {
      for (final entry in students.entries)
        if (entry.value.status == 'Active') entry.key: entry.value,
    };
  }

  final rows = schedules
      .map((r) {
        if (allowedIds != null) {
          if (allowedIds.isEmpty || !allowedIds.contains(r.studentId)) {
            return null;
          }
        }
        final s = students[r.studentId];
        if (s == null) return null;
        if (filters.activeOnly && s.status != 'Active') return null;

        if (r.date != null) {
          final tripDate = DateTime.fromMillisecondsSinceEpoch(r.date!);
          final day = DateTime.utc(tripDate.year, tripDate.month, tripDate.day);
          if (day.isBefore(_dateOnly(filters.dateStart)) ||
              day.isAfter(_dateOnly(filters.dateEnd))) {
            return null;
          }
        } else {
          final year = int.tryParse(r.year);
          if (year != null &&
              !calendarYearOverlapsRange(
                year,
                filters.dateStart,
                filters.dateEnd,
              )) {
            return null;
          }
        }

        double monthAmount(int month, double amount) {
          final year = int.tryParse(r.year);
          if (year == null) return amount;
          return calendarMonthOverlapsRange(
            year: year,
            month: month,
            rangeStart: filters.dateStart,
            rangeEnd: filters.dateEnd,
          )
              ? amount
              : 0;
        }

        return MissionPaymentReportRow(
          studentName: '${s.surname}, ${s.firstName}',
          tripSelected: r.tripSelected,
          date: r.date != null
              ? DateTime.fromMillisecondsSinceEpoch(r.date!)
              : null,
          amount: r.amount,
          mar: monthAmount(3, r.mar),
          apr: monthAmount(4, r.apr),
          may: monthAmount(5, r.may),
          jun: monthAmount(6, r.jun),
          jul: monthAmount(7, r.jul),
          aug: monthAmount(8, r.aug),
          sep: monthAmount(9, r.sep),
          oct: monthAmount(10, r.oct),
          comment: r.comment,
        );
      })
      .whereType<MissionPaymentReportRow>()
      .toList();
  rows.sort((a, b) => a.studentName.compareTo(b.studentName));
  return rows;
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

final missionLocationsReportDataProvider =
    FutureProvider.autoDispose<List<MissionLocationReportRow>>((ref) async {
  final db = ref.watch(appDatabaseProvider);
  final rows = await (db.select(db.missionLocations)
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .get();
  return rows
      .map(
        (r) => MissionLocationReportRow(
          name: r.name,
          description: r.description,
          isActive: r.isActive,
        ),
      )
      .toList();
});
