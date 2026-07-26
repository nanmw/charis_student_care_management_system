import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/change_sets_repository.dart';
import 'package:charis_student_care/domain/finance/session_payment_math.dart';
import 'package:charis_student_care/presentation/providers/academic_session_providers.dart';
import 'package:charis_student_care/presentation/providers/attendance_providers.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/ministry_providers.dart';
import 'package:charis_student_care/presentation/providers/mission_payment_providers.dart';
import 'package:charis_student_care/presentation/providers/settings_providers.dart';
import 'package:charis_student_care/presentation/providers/payment_providers.dart';
import 'package:charis_student_care/presentation/providers/scope_filter.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/test_providers.dart';

/// Reserved payload keys used for display only (excluded from "what changed").
const _reservedPayloadKeys = {
  'screen',
  'userDisplayName',
  'studentName',
  'studentYear',
  'studentMode',
  'version',
};

/// Human-readable labels for payload keys when building "what was updated".
const _payloadKeyLabels = <String, String>{
  'surname': 'Surname',
  'firstName': 'First name',
  'year': 'Year',
  'mode': 'Mode',
  'admissionYear': 'Admission year',
  'contactInfo': 'Contact info',
  'email': 'Email',
  'handbook': 'Handbook',
  'mediaRelease': 'Media release',
  'accidentWaiver': 'Accident waiver',
  'status': 'Status',
  'studentId': 'Student',
  'date': 'Date',
  'present': 'Present',
  'notes': 'Notes',
  'score': 'Score',
  'label': 'Label',
  'subjectId': 'Subject',
  'academicSession': 'Academic session',
  'jan': 'Pre-session payment (January)',
  'feb': 'February',
  'mar': 'March',
  'apr': 'April',
  'may': 'May',
  'jun': 'June',
  'jul': 'July',
  'aug': 'August',
  'sep': 'September',
  'oct': 'October',
  'nov': 'November',
  'dec': 'December',
  'lumpSum': 'Lump sum',
};

/// Enriched activity for dashboard display (parsed from [ChangeSet] payload).
class DashboardActivity {
  const DashboardActivity({
    required this.changeSet,
    this.studentDisplay,
    this.userDisplayName,
    this.screen,
    this.whatChanged,
  });

  final ChangeSet changeSet;
  final String? studentDisplay;
  final String? userDisplayName;
  final String? screen;
  final String? whatChanged;

  DateTime get timestamp => changeSet.timestamp;
  String get operation => changeSet.operation;
  String get table => changeSet.table;
}

/// Builds [DashboardActivity] from [ChangeSet] by parsing payload and deriving display strings.
DashboardActivity dashboardActivityFromChangeSet(ChangeSet changeSet) {
  Map<String, dynamic> payload = {};
  try {
    final decoded = jsonDecode(changeSet.payload);
    if (decoded is Map<String, dynamic>) {
      payload = decoded;
    }
  } on FormatException {
    // Corrupt JSON: leave payload empty so the activity row still renders.
  } on TypeError {
    // Unexpected payload shape: leave payload empty.
  }

  final studentName = payload['studentName'] as String?;
  final studentYear = payload['studentYear'] as String?;
  final studentMode = payload['studentMode'] as String?;
  String? studentDisplay;
  if (studentName != null && studentName.isNotEmpty) {
    final parts = <String>[studentName];
    if (studentYear != null &&
        studentYear.isNotEmpty &&
        studentMode != null &&
        studentMode.isNotEmpty) {
      parts.add('($studentYear / $studentMode)');
    } else if (studentYear != null && studentYear.isNotEmpty) {
      parts.add('($studentYear)');
    } else if (studentMode != null && studentMode.isNotEmpty) {
      parts.add('($studentMode)');
    }
    studentDisplay = parts.join(' ');
  }

  final userDisplayName = payload['userDisplayName'] as String?;
  final screen = payload['screen'] as String?;

  final changeKeys = payload.keys
      .where((k) => !_reservedPayloadKeys.contains(k) && payload[k] != null)
      .toList();
  final labels = changeKeys
      .map((k) => _payloadKeyLabels[k] ?? k)
      .where((l) => l.isNotEmpty)
      .toList();
  final whatChanged = labels.isEmpty ? null : labels.join(', ');

  return DashboardActivity(
    changeSet: changeSet,
    studentDisplay:
        studentDisplay?.trim().isEmpty == true ? null : studentDisplay,
    userDisplayName:
        userDisplayName?.trim().isEmpty == true ? null : userDisplayName,
    screen: screen?.trim().isEmpty == true ? null : screen,
    whatChanged: whatChanged?.trim().isEmpty == true ? null : whatChanged,
  );
}

/// One row in the dashboard summary table: metrics for a single cohort (year + mode).
class DashboardCohortSummary {
  const DashboardCohortSummary({
    required this.year,
    required this.mode,
    required this.studentCount,
    this.avgAttendancePercent,
    required this.outstandingTests,
    required this.failedTests,
    required this.passedTests,
    required this.totalBalance,
    required this.balanceDueExpectedMonthly,
  });

  final String year;
  final String mode;
  final int studentCount;
  final double? avgAttendancePercent;
  final int outstandingTests;
  final int failedTests;
  final int passedTests;
  final double totalBalance;
  /// Sum of (expected this month − paid this month) per student, clamped to ≥ 0. Shown as "Balance due as expected monthly".
  final double balanceDueExpectedMonthly;

  String get cohortLabel => '$year / $mode';
}

/// Fallback when no current session is set. Single year (session = Feb–Oct of that year).
String _defaultCurrentAcademicSession() {
  return DateTime.now().year.toString();
}

/// One row in the dashboard individual summary table: metrics for a single student.
class DashboardStudentSummary {
  const DashboardStudentSummary({
    required this.studentId,
    required this.displayName,
    required this.year,
    required this.mode,
    this.avgAttendancePercent,
    required this.outstandingTests,
    required this.failedTests,
    required this.passedTests,
    required this.totalBalance,
    required this.balanceDueExpectedMonthly,
    this.totalMinistryHours = 0.0,
    this.missionFund = 0.0,
  });

  final int studentId;
  final String displayName;
  final String year;
  final String mode;
  final double? avgAttendancePercent;
  final int outstandingTests;
  final int failedTests;
  final int passedTests;
  final double totalBalance;
  /// Balance due as expected for the current month (expected this month − paid this month, ≥ 0).
  final double balanceDueExpectedMonthly;
  final double totalMinistryHours;
  final double missionFund;

  String get yearModeLabel => '$year / $mode';
}

/// One row in the Recent Activities report / audit log.
class ActivityReportRow {
  const ActivityReportRow({
    required this.timestamp,
    required this.user,
    this.student,
    required this.operation,
    required this.table,
    this.screen,
    this.whatChanged,
  });

  final DateTime timestamp;
  final String user;
  final String? student;
  final String operation;
  final String table;
  final String? screen;
  final String? whatChanged;
}

/// Filters for the Recent Activities report.
class ActivityReportFilters {
  const ActivityReportFilters({
    required this.dateStart,
    required this.dateEnd,
    this.userFilter,
    this.screenFilter,
    this.tableFilter,
  });

  final DateTime dateStart;
  final DateTime dateEnd;
  final String? userFilter;
  final String? screenFilter;
  final List<String>? tableFilter;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ActivityReportFilters) return false;
    return dateStart == other.dateStart &&
        dateEnd == other.dateEnd &&
        userFilter == other.userFilter &&
        screenFilter == other.screenFilter &&
        _listEquals(tableFilter, other.tableFilter);
  }

  @override
  int get hashCode {
    final tablesHash =
        tableFilter == null ? null : Object.hashAll(tableFilter!);
    return Object.hash(dateStart, dateEnd, userFilter, screenFilter, tablesHash);
  }
}

bool _listEquals(List<String>? a, List<String>? b) {
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Resolve the student id affected by a [changeSet] when possible.
Future<int?> _studentIdForChangeSet(AppDatabase db, ChangeSet changeSet) async {
  final table = changeSet.table;
  final recordId = int.tryParse(changeSet.recordId);
  if (recordId == null) return null;

  switch (table) {
    case 'students':
      return recordId;
    case 'attendance':
      final row = await (db.select(db.attendance)
            ..where((t) => t.id.equals(recordId)))
          .getSingleOrNull();
      return row?.studentId;
    case 'tests':
      final row = await (db.select(db.tests)
            ..where((t) => t.id.equals(recordId)))
          .getSingleOrNull();
      return row?.studentId;
    case 'ministry_entries':
      final row = await (db.select(db.ministryEntries)
            ..where((t) => t.id.equals(recordId)))
          .getSingleOrNull();
      return row?.studentId;
    default:
      // Other tables are either global or resolved differently; they are not considered
      // student-scoped for facilitators.
      return null;
  }
}

final changeSetsRepositoryProvider = Provider<ChangeSetsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ChangeSetsRepository(db);
});

/// Average attendance percentage across all recorded attendance.
/// Scoped for facilitators (class + mode) so the key card matches summary tables.
final averageAttendancePercentageProvider =
    StreamProvider.autoDispose<double?>((ref) {
  final repo = ref.watch(attendanceRepositoryProvider);
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
  final allowedIdsAsync = ref.watch(allowedStudentIdsStreamProvider);

  return scopeAsync.when(
    data: (scope) => allowedIdsAsync.when(
      data: (ids) {
        final studentIds = studentIdsFilterForScope(scope, ids);
        return repo
            .watchAttendanceForStudents(studentIds: studentIds)
            .map((records) {
          if (records.isEmpty) return null;
          final byStudent = <int, List<AttendanceData>>{};
          for (final r in records) {
            byStudent.putIfAbsent(r.studentId, () => []).add(r);
          }
          if (byStudent.isEmpty) return null;
          final percentages = <double>[];
          for (final studentRecords in byStudent.values) {
            if (studentRecords.isEmpty) continue;
            final present =
                studentRecords.where((r) => r.present == 1).length;
            percentages.add((present / studentRecords.length) * 100);
          }
          if (percentages.isEmpty) return null;
          return percentages.reduce((a, b) => a + b) / percentages.length;
        });
      },
      loading: () => const Stream.empty(),
      error: (e, st) => Stream.error(e, st),
    ),
    loading: () => const Stream.empty(),
    error: (e, st) => Stream.error(e, st),
  );
});

/// Total outstanding tests count across all active students for the current academic session.
/// Outstanding = tests that the cohort (same class + mode) has sat for in the session
/// which a given student has not yet taken (aligned with student summary logic).
final dashboardOutstandingTestsProvider =
    StreamProvider.autoDispose<int>((ref) {
  final summariesAsync = ref.watch(dashboardStudentSummaryProvider('Active'));
  return summariesAsync.when(
    data: (summaries) => Stream.value(
      summaries.fold<int>(0, (sum, s) => sum + s.outstandingTests),
    ),
    loading: () => const Stream.empty(),
    error: (e, st) => Stream.error(e, st),
  );
});

/// Focus period for dashboard finance KPIs.
enum DashboardFocusPeriod {
  thisMonth,
  thisTerm,
  thisYear,
}

/// Which focus period is selected. Default [DashboardFocusPeriod.thisMonth].
final dashboardFocusPeriodProvider =
    StateProvider.autoDispose<DashboardFocusPeriod>((ref) => DashboardFocusPeriod.thisMonth);

/// Session months for the current academic session (for month dropdown when focus is This Month).
final dashboardSelectableMonthsProvider = Provider.autoDispose<List<(int year, int month)>>((ref) {
  final code = ref.watch(currentAcademicSessionProvider).valueOrNull?.trim();
  final sessionCode = (code == null || code.isEmpty) ? _defaultCurrentAcademicSession() : code;
  return sessionMonthsForCode(sessionCode);
});

/// Explicitly selected month (year, month) when focus is This Month. Null = use current month.
final dashboardSelectedMonthProvider =
    StateProvider.autoDispose<(int year, int month)?>((ref) => null);

/// Effective period as list of (year, month) for the current focus and selected month.
/// Single month for thisMonth, term months for thisTerm, all session months (Feb–Oct) for thisYear.
final dashboardEffectivePeriodProvider = Provider.autoDispose<List<(int year, int month)>>((ref) {
  final focus = ref.watch(dashboardFocusPeriodProvider);
  final selected = ref.watch(dashboardSelectedMonthProvider);
  final sessionCode = ref.watch(currentAcademicSessionProvider).valueOrNull;
  final code = (sessionCode?.trim().isEmpty ?? true)
      ? _defaultCurrentAcademicSession()
      : (sessionCode ?? _defaultCurrentAcademicSession());
  final sessionMonths = sessionMonthsForCode(code);
  if (sessionMonths.isEmpty) return [];
  final now = DateTime.now();
  final currentYear = now.year;
  final currentMonth = now.month;
  final currentIndex = sessionMonths.indexWhere((m) => m.$1 == currentYear && m.$2 == currentMonth);

  switch (focus) {
    case DashboardFocusPeriod.thisMonth:
      if (selected != null) {
        final i = sessionMonths.indexWhere((m) => m.$1 == selected.$1 && m.$2 == selected.$2);
        if (i >= 0) return [sessionMonths[i]];
      }
      if (currentIndex >= 0) return [sessionMonths[currentIndex]];
      return sessionMonths.isNotEmpty ? [sessionMonths.last] : [];
    case DashboardFocusPeriod.thisTerm:
      return _termMonthsForSession(sessionMonths, currentIndex >= 0 ? currentIndex : sessionMonths.length - 1);
    case DashboardFocusPeriod.thisYear:
      return List.from(sessionMonths);
  }
});

/// 3 terms per session (Feb–Oct): Term 1 Feb–Apr, Term 2 May–Jul, Term 3 Aug–Oct.
List<(int year, int month)> _termMonthsForSession(
  List<(int year, int month)> sessionMonths,
  int currentMonthIndex,
) {
  const termLengths = [3, 3, 3]; // months per term
  int start = 0;
  for (final len in termLengths) {
    final end = start + len;
    if (currentMonthIndex < end) {
      return sessionMonths.sublist(start, end.clamp(0, sessionMonths.length));
    }
    start = end;
  }
  return sessionMonths.sublist(start.clamp(0, sessionMonths.length - 1), sessionMonths.length);
}

/// Monthly finance snapshot for the dashboard (selected month = current month by default).
class DashboardMonthlyFinance {
  const DashboardMonthlyFinance({
    required this.monthName,
    required this.year,
    required this.expectedPlusBf,
    required this.paidThisMonth,
    required this.balanceDue,
    required this.balanceDueThisMonth,
    required this.collectionRatePercent,
    this.previousMonthBalanceDue,
    this.deltaPercentVsPreviousMonth,
  });

  final String monthName;
  final int year;
  final double expectedPlusBf;
  final double paidThisMonth;
  final double balanceDue;
  /// Balance still due for this month (expected this month − paid this month). Primary KPI "Balance Due – This Month".
  final double balanceDueThisMonth;
  /// % of expected fees collected this month (0–100).
  final double collectionRatePercent;
  /// Balance due for the previous month (for delta display).
  final double? previousMonthBalanceDue;
  /// Percent change vs previous month (positive = worse). Null if no previous month.
  final double? deltaPercentVsPreviousMonth;
}

/// Aged arrears breakdown: amounts in each bucket (0–30, 31–60, 61–90, 90+ days overdue).
class AgedArrearsSnapshot {
  const AgedArrearsSnapshot({
    required this.bucket0to30,
    required this.bucket31to60,
    required this.bucket61to90,
    required this.bucket90Plus,
  });

  final double bucket0to30;
  final double bucket31to60;
  final double bucket61to90;
  final double bucket90Plus;

  double get total =>
      bucket0to30 + bucket31to60 + bucket61to90 + bucket90Plus;
}

/// Single point in the monthly balance due trend (per month).
class DashboardMonthlyBalancePoint {
  const DashboardMonthlyBalancePoint({
    required this.year,
    required this.month,
    required this.balanceDue,
  });

  final int year;
  final int month;
  final double balanceDue;
}

/// Total balance due across all active students for the current academic session. Scoped for facilitators (class + mode).
final totalBalanceDueProvider = StreamProvider.autoDispose<double>((ref) {
  final paymentRepo = ref.watch(paymentRepositoryProvider);
  final studentRepo = ref.watch(studentRepositoryProvider);
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
  final sessionAsync = ref.watch(currentAcademicSessionProvider);
  final sessionTuition = ref.watch(sessionTuitionAmountProvider);
  return sessionAsync.when(
    data: (sessionCode) {
      final code = (sessionCode?.trim().isEmpty ?? true)
          ? _defaultCurrentAcademicSession()
          : sessionCode!;
      return scopeAsync.when(
        data: (scope) {
          final studentsStream = (scope != null &&
                  (scope.classIds == null || scope.classIds!.isEmpty))
              ? Stream<List<Student>>.value([])
              : studentRepo.watchStudents(
                  statusFilter: 'Active',
                  classIds: scope?.classIds,
                  mode: scope?.mode,
                );
          return studentsStream.asyncExpand((students) {
            final ids = students.map((s) => s.id).toList();
            final payStream = paymentRepo.watchPaymentsForSession(
              code,
              studentIds: studentIdsFilterForScope(scope, ids),
            );
            return payStream.map((payments) {
              double totalBalance = 0.0;
              for (final student in students) {
                final totalPaid =
                    totalSessionPaidForStudent(payments, student.id);
                final balance = sessionTuition - totalPaid;
                if (balance > 0) totalBalance += balance;
              }
              return totalBalance;
            });
          });
        },
        loading: () => const Stream.empty(),
        error: (e, st) => Stream.error(e, st),
      );
    },
    loading: () => const Stream.empty(),
    error: (e, st) => Stream.error(e, st),
  );
});

/// Monthly finance for dashboard: Total Expected (month + B/F), Total Paid, Total Balance Due.
/// Uses [dashboardEffectivePeriodProvider]; single month or aggregated for term/year.
final dashboardMonthlyFinanceProvider =
    StreamProvider.autoDispose<DashboardMonthlyFinance>((ref) {
  final paymentRepo = ref.watch(paymentRepositoryProvider);
  final studentRepo = ref.watch(studentRepositoryProvider);
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
  final sessionAsync = ref.watch(currentAcademicSessionProvider);
  final monthlyTuition = ref.watch(monthlyTuitionFeeProvider).valueOrNull ??
      defaultMonthlyTuitionFee;
  final sessionTuition = ref.watch(sessionTuitionAmountProvider);
  final effectivePeriod = ref.watch(dashboardEffectivePeriodProvider);
  final now = DateTime.now();
  final fallbackYear = now.year;
  final fallbackMonth = now.month;

  if (effectivePeriod.isEmpty) {
    return Stream.value(
      DashboardMonthlyFinance(
        monthName: _monthName(fallbackYear, fallbackMonth),
        year: fallbackYear,
        expectedPlusBf: 0.0,
        paidThisMonth: 0.0,
        balanceDue: 0.0,
        balanceDueThisMonth: 0.0,
        collectionRatePercent: 0.0,
      ),
    );
  }

  final firstMonth = effectivePeriod.first;
  final lastMonth = effectivePeriod.last;
  final focus = ref.watch(dashboardFocusPeriodProvider);
  final periodLabel = focus == DashboardFocusPeriod.thisMonth
      ? _monthName(lastMonth.$1, lastMonth.$2)
      : focus == DashboardFocusPeriod.thisTerm
          ? (firstMonth.$2 <= 4 ? 'Term 1' : (firstMonth.$2 <= 7 ? 'Term 2' : 'Term 3'))
          : 'Full session';

  return sessionAsync.when(
    data: (sessionCode) {
      final code = (sessionCode?.trim().isEmpty ?? true)
          ? _defaultCurrentAcademicSession()
          : sessionCode!;
      return scopeAsync.when(
        data: (scope) {
          final studentsStream = (scope != null &&
                  (scope.classIds == null || scope.classIds!.isEmpty))
              ? Stream<List<Student>>.value([])
              : studentRepo.watchStudents(
                  statusFilter: 'Active',
                  classIds: scope?.classIds,
                  mode: scope?.mode,
                );
          return studentsStream.asyncExpand((students) {
            final ids = students.map((s) => s.id).toList();
            final payStream = paymentRepo.watchPaymentsForSession(
              code,
              studentIds: studentIdsFilterForScope(scope, ids),
            );
            return payStream.map((payments) {
              final byStudentYear = <(int, int), Payment>{};
              for (final p in payments) {
                final y = int.tryParse(p.year);
                if (y != null) byStudentYear[(p.studentId, y)] = p;
              }

              final sessionMonths = sessionMonthsForCode(code);
              final firstIndex = sessionMonths.indexWhere(
                (m) => m.$1 == firstMonth.$1 && m.$2 == firstMonth.$2,
              );
              final numMonthsBefore = firstIndex >= 0 ? firstIndex : 0;
              final expectedPerMonth = monthlyTuition;

              double balanceBf = 0.0;
              double paidInPeriodTotal = 0.0;
              double totalBalanceDue = 0.0;

              for (final student in students) {
                final paidPrior = paidPriorIncludingLumpSum(
                  studentId: student.id,
                  sessionMonths: sessionMonths,
                  numMonthsBefore: numMonthsBefore,
                  byStudentYear: byStudentYear,
                );
                final expectedPrior = numMonthsBefore * expectedPerMonth;
                balanceBf += (expectedPrior - paidPrior).clamp(0.0, double.infinity);

                for (final (y, m) in effectivePeriod) {
                  final p = byStudentYear[(student.id, y)];
                  if (p != null) {
                    paidInPeriodTotal += paymentAmountForMonth(p, y, m);
                  }
                }

                final totalPaid = sessionTotalPaidIncludingLumpSum(
                  studentId: student.id,
                  sessionMonths: sessionMonths,
                  byStudentYear: byStudentYear,
                );
                final balance = sessionTuition - totalPaid;
                if (balance > 0) totalBalanceDue += balance;
              }

              final expectedInPeriod =
                  effectivePeriod.length * expectedPerMonth * students.length;
              final balanceDueForPeriod =
                  (expectedInPeriod - paidInPeriodTotal).clamp(0.0, double.infinity);
              final collectionRatePercent = expectedInPeriod > 0
                  ? (paidInPeriodTotal / expectedInPeriod) * 100
                  : 0.0;

              double? previousMonthBalanceDue;
              double? deltaPercentVsPreviousMonth;
              if (effectivePeriod.length == 1) {
                final prevIndex = sessionMonths.indexOf(firstMonth) - 1;
                if (prevIndex >= 0 && prevIndex < sessionMonths.length) {
                  final (prevYear, prevMonth) = sessionMonths[prevIndex];
                  double prevPaid = 0.0;
                  for (final student in students) {
                    final p = byStudentYear[(student.id, prevYear)];
                    if (p != null) {
                      prevPaid += paymentAmountForMonth(p, prevYear, prevMonth);
                    }
                  }
                  final prevExpected = students.length * expectedPerMonth;
                  previousMonthBalanceDue =
                      (prevExpected - prevPaid).clamp(0.0, double.infinity);
                  final prev = previousMonthBalanceDue;
                  if (prev > 0) {
                    deltaPercentVsPreviousMonth =
                        ((balanceDueForPeriod - prev) / prev) * 100;
                  }
                }
              }

              return DashboardMonthlyFinance(
                monthName: periodLabel,
                year: lastMonth.$1,
                expectedPlusBf: balanceBf + expectedInPeriod,
                paidThisMonth: paidInPeriodTotal,
                balanceDue: totalBalanceDue,
                balanceDueThisMonth: balanceDueForPeriod,
                collectionRatePercent: collectionRatePercent,
                previousMonthBalanceDue: previousMonthBalanceDue,
                deltaPercentVsPreviousMonth: deltaPercentVsPreviousMonth,
              );
            });
          });
        },
        loading: () => const Stream.empty(),
        error: (e, st) => Stream.error(e, st),
      );
    },
    loading: () => const Stream.empty(),
    error: (e, st) => Stream.error(e, st),
  );
});

/// Aged arrears breakdown: 0–30, 31–60, 61–90, 90+ days (mapped from current/previous months' shortfalls).
final dashboardAgedArrearsProvider =
    StreamProvider.autoDispose<AgedArrearsSnapshot>((ref) {
  final paymentRepo = ref.watch(paymentRepositoryProvider);
  final studentRepo = ref.watch(studentRepositoryProvider);
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
  final sessionAsync = ref.watch(currentAcademicSessionProvider);
  final monthlyTuition = ref.watch(monthlyTuitionFeeProvider).valueOrNull ??
      defaultMonthlyTuitionFee;
  final effectivePeriod = ref.watch(dashboardEffectivePeriodProvider);

  return sessionAsync.when(
    data: (sessionCode) {
      final code = (sessionCode?.trim().isEmpty ?? true)
          ? _defaultCurrentAcademicSession()
          : sessionCode!;
      return scopeAsync.when(
        data: (scope) {
          final studentsStream = (scope != null &&
                  (scope.classIds == null || scope.classIds!.isEmpty))
              ? Stream<List<Student>>.value([])
              : studentRepo.watchStudents(
                  statusFilter: 'Active',
                  classIds: scope?.classIds,
                  mode: scope?.mode,
                );
          return studentsStream.asyncExpand((students) {
            final ids = students.map((s) => s.id).toList();
            final payStream = paymentRepo.watchPaymentsForSession(
              code,
              studentIds: studentIdsFilterForScope(scope, ids),
            );
            return payStream.map((payments) {
              final byStudentYear = <(int, int), Payment>{};
              for (final p in payments) {
                final y = int.tryParse(p.year);
                if (y != null) byStudentYear[(p.studentId, y)] = p;
              }
              final sessionMonths = sessionMonthsForCode(code);
              final lastMonth = effectivePeriod.isNotEmpty
                  ? effectivePeriod.last
                  : (sessionMonths.isNotEmpty
                      ? sessionMonths.last
                      : (DateTime.now().year, DateTime.now().month));
              final expectedPerMonth = monthlyTuition;
              final currentIndex = sessionMonths.indexWhere(
                (m) => m.$1 == lastMonth.$1 && m.$2 == lastMonth.$2,
              );
              if (currentIndex < 0) {
                return const AgedArrearsSnapshot(
                  bucket0to30: 0,
                  bucket31to60: 0,
                  bucket61to90: 0,
                  bucket90Plus: 0,
                );
              }
              double bucket0 = 0, bucket1 = 0, bucket2 = 0, bucket3 = 0;
              for (var i = 0; i <= currentIndex && i < sessionMonths.length; i++) {
                final (y, m) = sessionMonths[i];
                double shortfall = 0.0;
                for (final student in students) {
                  final p = byStudentYear[(student.id, y)];
                  final paid = p != null ? paymentAmountForMonth(p, y, m) : 0.0;
                  shortfall +=
                      (expectedPerMonth - paid).clamp(0.0, double.infinity);
                }
                final monthsAgo = currentIndex - i;
                if (monthsAgo == 0) {
                  bucket0 += shortfall;
                } else if (monthsAgo == 1) {
                  bucket1 += shortfall;
                } else if (monthsAgo == 2) {
                  bucket2 += shortfall;
                } else {
                  bucket3 += shortfall;
                }
              }
              return AgedArrearsSnapshot(
                bucket0to30: bucket0,
                bucket31to60: bucket1,
                bucket61to90: bucket2,
                bucket90Plus: bucket3,
              );
            });
          });
        },
        loading: () => const Stream.empty(),
        error: (e, st) => Stream.error(e, st),
      );
    },
    loading: () => const Stream.empty(),
    error: (e, st) => Stream.error(e, st),
  );
});

/// Monthly balance due (expected − paid for that month) for the last 12 months.
/// Each point includes the calendar year and month so the UI can show month labels on hover.
final dashboardMonthlyBalanceTrendProvider =
    StreamProvider.autoDispose<List<DashboardMonthlyBalancePoint>>((ref) {
  final paymentRepo = ref.watch(paymentRepositoryProvider);
  final studentRepo = ref.watch(studentRepositoryProvider);
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
  final sessionAsync = ref.watch(currentAcademicSessionProvider);
  final monthlyTuition = ref.watch(monthlyTuitionFeeProvider).valueOrNull ??
      defaultMonthlyTuitionFee;
  final effectivePeriod = ref.watch(dashboardEffectivePeriodProvider);

  return sessionAsync.when(
    data: (sessionCode) {
      final code = (sessionCode?.trim().isEmpty ?? true)
          ? _defaultCurrentAcademicSession()
          : sessionCode!;
      return scopeAsync.when(
        data: (scope) {
          final studentsStream = (scope != null &&
                  (scope.classIds == null || scope.classIds!.isEmpty))
              ? Stream<List<Student>>.value([])
              : studentRepo.watchStudents(
                  statusFilter: 'Active',
                  classIds: scope?.classIds,
                  mode: scope?.mode,
                );
          return studentsStream.asyncExpand((students) {
            final ids = students.map((s) => s.id).toList();
            final payStream = paymentRepo.watchPaymentsForSession(
              code,
              studentIds: studentIdsFilterForScope(scope, ids),
            );
            return payStream.map((payments) {
              final byStudentYear = <(int, int), Payment>{};
              for (final p in payments) {
                final y = int.tryParse(p.year);
                if (y != null) byStudentYear[(p.studentId, y)] = p;
              }
              final sessionMonths = sessionMonthsForCode(code);
              final lastMonth = effectivePeriod.isNotEmpty
                  ? effectivePeriod.last
                  : (sessionMonths.isNotEmpty
                      ? sessionMonths.last
                      : (DateTime.now().year, DateTime.now().month));
              final expectedPerMonth = monthlyTuition;
              final currentIndex = sessionMonths.indexWhere(
                (m) => m.$1 == lastMonth.$1 && m.$2 == lastMonth.$2,
              );
              final points = <DashboardMonthlyBalancePoint>[];
              final start = (currentIndex - 11).clamp(0, sessionMonths.length);
              final end = currentIndex + 1;
              for (var i = start; i < end && i < sessionMonths.length; i++) {
                final (y, m) = sessionMonths[i];
                double shortfall = 0.0;
                for (final student in students) {
                  final p = byStudentYear[(student.id, y)];
                  final paid = p != null ? paymentAmountForMonth(p, y, m) : 0.0;
                  shortfall +=
                      (expectedPerMonth - paid).clamp(0.0, double.infinity);
                }
                points.add(
                  DashboardMonthlyBalancePoint(
                    year: y,
                    month: m,
                    balanceDue: shortfall,
                  ),
                );
              }
              return points.length > 12
                  ? points.sublist(points.length - 12)
                  : points;
            });
          });
        },
        loading: () => const Stream.empty(),
        error: (e, st) => Stream.error(e, st),
      );
    },
    loading: () => const Stream.empty(),
    error: (e, st) => Stream.error(e, st),
  );
});

String _monthName(int year, int month) {
  try {
    final d = DateTime(year, month);
    return _monthNames[d.month - 1];
  } catch (_) {
    return '—';
  }
}

const List<String> _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Recent activities from change sets (raw window; prefer [recentActivitiesEnrichedProvider]).
final recentActivitiesProvider =
    StreamProvider.autoDispose<List<ChangeSet>>((ref) {
  final repo = ref.watch(changeSetsRepositoryProvider);
  // Larger window so role/scope filtering still yields up to 10 items.
  return repo.watchRecentChanges(limit: 100);
});

/// Recent activities enriched with parsed payload, filtered by role and facilitator scope.
/// Hides payment tables when the user cannot manage financials; facilitators only see
/// activities tied to students in their class/mode scope. Returns up to 10 items.
final recentActivitiesEnrichedProvider =
    StreamProvider.autoDispose<List<DashboardActivity>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final repo = ref.watch(changeSetsRepositoryProvider);
  final auth = ref.watch(authStateProvider).valueOrNull;
  final role = auth is Authenticated ? auth.role : null;
  final canManageFinancials =
      role != null && RolePermissions.canManageFinancials(role);
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);

  return scopeAsync.when(
    data: (scope) {
      // Facilitators without class assignment see nothing student-scoped.
      if (role == UserRole.facilitator &&
          (scope == null ||
              scope.classIds == null ||
              scope.classIds!.isEmpty)) {
        return Stream.value(const <DashboardActivity>[]);
      }

      return repo.watchRecentChanges(limit: 100).asyncMap((list) async {
        final filtered = <DashboardActivity>[];
        for (final cs in list) {
          final isPaymentTable =
              cs.table == 'payments' || cs.table == 'mission_payments';
          if (isPaymentTable && !canManageFinancials) {
            continue;
          }

          if (role == UserRole.facilitator) {
            final studentId = await _studentIdForChangeSet(db, cs);
            if (studentId == null) continue;

            final student = await (db.select(db.students)
                  ..where((t) => t.id.equals(studentId)))
                .getSingleOrNull();
            if (student == null) continue;

            if (!scope!.classIds!.contains(student.classId)) continue;
            if (scope.mode != null && scope.mode!.trim().isNotEmpty) {
              if ((student.mode ?? '').trim() != scope.mode!.trim()) {
                continue;
              }
            }
          }

          filtered.add(dashboardActivityFromChangeSet(cs));
          if (filtered.length >= 10) break;
        }
        return filtered;
      });
    },
    loading: () => const Stream.empty(),
    error: (e, st) => Stream.error(e, st),
  );
});

/// Report data for Recent Activities / Audit Log, with role- and scope-based filtering.
final recentActivitiesReportProvider =
    FutureProvider.autoDispose.family<List<ActivityReportRow>, ActivityReportFilters>(
  (ref, filters) async {
    final db = ref.watch(appDatabaseProvider);
    final auth = ref.watch(authStateProvider).valueOrNull;
    final role = auth is Authenticated ? auth.role : null;

    // Facilitator scope (classIds + mode) when applicable.
    final scope = role == UserRole.facilitator
        ? await ref.watch(currentUserFacilitatorScopeProvider.future)
        : null;

    final canManageFinancials =
        role != null && RolePermissions.canManageFinancials(role);

    // Base query: fetch all change-sets, we'll filter by date/user/scope in Dart.
    final allChangeSets = await (db.select(db.changeSets)).get();
    final changeSets = allChangeSets.where((cs) {
      final ts = cs.timestamp;
      if (ts.isBefore(filters.dateStart) || ts.isAfter(filters.dateEnd)) {
        return false;
      }
      if (filters.tableFilter != null && filters.tableFilter!.isNotEmpty) {
        if (!filters.tableFilter!.contains(cs.table)) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final rows = <ActivityReportRow>[];

    for (final cs in changeSets) {
      final isPaymentTable =
          cs.table == 'payments' || cs.table == 'mission_payments';
      if (isPaymentTable && !canManageFinancials) {
        // All payment-related activities are admin/financial-role only.
        continue;
      }

      final activity = dashboardActivityFromChangeSet(cs);

      // Screen filter (substring match, case-insensitive) on the derived screen label.
      if (filters.screenFilter != null &&
          filters.screenFilter!.trim().isNotEmpty) {
        final needle = filters.screenFilter!.trim().toLowerCase();
        final screen = activity.screen?.toLowerCase() ?? '';
        if (!screen.contains(needle)) continue;
      }

      // User filter on display name or userId.
      final userDisplayName = activity.userDisplayName ?? cs.userId;
      if (filters.userFilter != null &&
          filters.userFilter!.trim().isNotEmpty) {
        final needle = filters.userFilter!.trim().toLowerCase();
        if (!userDisplayName.toLowerCase().contains(needle)) continue;
      }

      // Facilitator: only activities tied to students within their scope (class + mode),
      // and never payments (handled above).
      if (role == UserRole.facilitator) {
        if (scope == null ||
            scope.classIds == null ||
            scope.classIds!.isEmpty) {
          continue;
        }
        final studentId = await _studentIdForChangeSet(db, cs);
        if (studentId == null) continue;

        final student = await (db.select(db.students)
              ..where((t) => t.id.equals(studentId)))
            .getSingleOrNull();
        if (student == null) continue;

        if (!scope.classIds!.contains(student.classId)) continue;
        if (scope.mode != null && scope.mode!.trim().isNotEmpty) {
          if ((student.mode ?? '').trim() != scope.mode!.trim()) continue;
        }
      }

      rows.add(
        ActivityReportRow(
          timestamp: activity.timestamp,
          user: userDisplayName,
          student: activity.studentDisplay,
          operation: activity.operation,
          table: activity.table,
          screen: activity.screen,
          whatChanged: activity.whatChanged,
        ),
      );
    }

    return rows;
  },
);

/// Summary table rows by cohort (class + mode). Scoped for facilitators (class + mode). Uses current academic session for payments.
final dashboardCohortSummaryProvider =
    StreamProvider.autoDispose<List<DashboardCohortSummary>>((ref) {
  final studentRepo = ref.watch(studentRepositoryProvider);
  final paymentRepo = ref.watch(paymentRepositoryProvider);
  final attendanceRepo = ref.watch(attendanceRepositoryProvider);
  final testRepo = ref.watch(testRepositoryProvider);
  final sessionRepo = ref.watch(academicSessionRepositoryProvider);
  final classes = ref.watch(allClassesFutureProvider).valueOrNull ?? [];
  final classIdToName = {null: '—', for (final c in classes) c.id: c.name};
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
  final allowedIdsAsync = ref.watch(allowedStudentIdsStreamProvider);
  final effectivePeriod = ref.watch(dashboardEffectivePeriodProvider);
  final monthlyTuition = ref.watch(monthlyTuitionFeeProvider).valueOrNull ??
      defaultMonthlyTuitionFee;
  final sessionTuition = ref.watch(sessionTuitionAmountProvider);

  return scopeAsync.when(
    data: (scope) => allowedIdsAsync.when(
      data: (ids) {
        final studentsStream = (scope != null &&
                (scope.classIds == null || scope.classIds!.isEmpty))
            ? Stream<List<Student>>.value([])
            : studentRepo.watchStudents(
                statusFilter: 'Active',
                classIds: scope?.classIds,
                mode: scope?.mode,
              );
        final sessionStream = sessionRepo.watchCurrentSession();
        final paymentsStream = sessionStream.asyncExpand((sessionCode) {
          final code = (sessionCode?.trim().isEmpty ?? true)
              ? _defaultCurrentAcademicSession()
              : sessionCode!;
              return paymentRepo.watchPaymentsForSession(
                code,
                studentIds: studentIdsFilterForScope(scope, ids),
              );
        });
        final attendanceStream = attendanceRepo.watchAttendanceForStudents(
          studentIds: studentIdsFilterForScope(scope, ids),
        );
        return _combineDashboardStreams(
          studentsStream: studentsStream,
          paymentsStream: paymentsStream,
          testsStream: testRepo.watchAllTests(),
          attendanceStream: attendanceStream,
          sessionStream: sessionStream,
          classIdToName: classIdToName,
          effectivePeriod: effectivePeriod,
          monthlyTuition: monthlyTuition,
          sessionTuition: sessionTuition,
          compute: _computeCohortSummaries,
        );
      },
      loading: () => const Stream.empty(),
      error: (e, st) => Stream.error(e, st),
    ),
    loading: () => const Stream.empty(),
    error: (e, st) => Stream.error(e, st),
  );
});

/// Summary table rows: one per student (filtered by [statusFilter]). Scoped for facilitators (class + mode). Uses current academic session for payments and missions.
final dashboardStudentSummaryProvider = StreamProvider.autoDispose
    .family<List<DashboardStudentSummary>, String?>((ref, statusFilter) {
  final studentRepo = ref.watch(studentRepositoryProvider);
  final paymentRepo = ref.watch(paymentRepositoryProvider);
  final attendanceRepo = ref.watch(attendanceRepositoryProvider);
  final testRepo = ref.watch(testRepositoryProvider);
  final ministryRepo = ref.watch(ministryEntryRepositoryProvider);
  final missionRepo = ref.watch(missionPaymentRepositoryProvider);
  final sessionRepo = ref.watch(academicSessionRepositoryProvider);
  final classes = ref.watch(allClassesFutureProvider).valueOrNull ?? [];
  final classIdToName = {null: '—', for (final c in classes) c.id: c.name};
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
  final allowedIdsAsync = ref.watch(allowedStudentIdsStreamProvider);
  final effectivePeriod = ref.watch(dashboardEffectivePeriodProvider);
  final monthlyTuition = ref.watch(monthlyTuitionFeeProvider).valueOrNull ??
      defaultMonthlyTuitionFee;
  final sessionTuition = ref.watch(sessionTuitionAmountProvider);

  return scopeAsync.when(
    data: (scope) => allowedIdsAsync.when(
      data: (ids) {
        final studentsStream = (scope != null &&
                (scope.classIds == null || scope.classIds!.isEmpty))
            ? Stream<List<Student>>.value([])
            : studentRepo.watchStudents(
                statusFilter: statusFilter,
                classIds: scope?.classIds,
                mode: scope?.mode,
              );
        final sessionStream = sessionRepo.watchCurrentSession();
        final paymentsStream = sessionStream.asyncExpand((sessionCode) {
          final code = (sessionCode?.trim().isEmpty ?? true)
              ? _defaultCurrentAcademicSession()
              : sessionCode!;
              return paymentRepo.watchPaymentsForSession(
                code,
                studentIds: studentIdsFilterForScope(scope, ids),
              );
        });
        final missionScheduleStream = sessionStream.asyncExpand((sessionCode) {
          final code = (sessionCode?.trim().isEmpty ?? true)
              ? _defaultCurrentAcademicSession()
              : sessionCode!;
          return missionRepo.watchForSession(code);
        });
        final attendanceStream = attendanceRepo.watchAttendanceForStudents(
          studentIds: studentIdsFilterForScope(scope, ids),
        );
        return _combineStudentSummaryStreams(
          studentsStream: studentsStream,
          paymentsStream: paymentsStream,
          testsStream: testRepo.watchAllTests(),
          attendanceStream: attendanceStream,
          ministryHoursStream: ministryRepo.watchTotalHoursByStudent(),
          missionScheduleStream: missionScheduleStream,
          sessionStream: sessionStream,
          classIdToName: classIdToName,
          effectivePeriod: effectivePeriod,
          monthlyTuition: monthlyTuition,
          sessionTuition: sessionTuition,
        );
      },
      loading: () => const Stream.empty(),
      error: (e, st) => Stream.error(e, st),
    ),
    loading: () => const Stream.empty(),
    error: (e, st) => Stream.error(e, st),
  );
});

Stream<T> _combineDashboardStreams<T>({
  required Stream<List<Student>> studentsStream,
  required Stream<List<Payment>> paymentsStream,
  required Stream<List<Test>> testsStream,
  required Stream<List<AttendanceData>> attendanceStream,
  required Stream<String?> sessionStream,
  Map<int?, String> classIdToName = const {},
  required List<(int, int)> effectivePeriod,
  required double monthlyTuition,
  required double sessionTuition,
  required T Function(
    List<Student>,
    List<Payment>,
    List<Test>,
    List<AttendanceData>,
    String,
    Map<int?, String>,
    List<(int, int)>,
    double,
    double,
  ) compute,
}) {
  List<Student>? students;
  List<Payment>? payments;
  List<Test>? tests;
  List<AttendanceData>? attendance;
  String? session;

  final controller = StreamController<T>();

  void emit() {
    if (students == null ||
        payments == null ||
        tests == null ||
        attendance == null) {
      return;
    }
    final currentSession = (session?.trim().isEmpty ?? true)
        ? _defaultCurrentAcademicSession()
        : session!;
    controller.add(
      compute(
        students!,
        payments!,
        tests!,
        attendance!,
        currentSession,
        classIdToName,
        effectivePeriod,
        monthlyTuition,
        sessionTuition,
      ),
    );
  }

  final subStudents = studentsStream.listen((s) {
    students = s;
    emit();
  });
  final subPayments = paymentsStream.listen((p) {
    payments = p;
    emit();
  });
  final subTests = testsStream.listen((t) {
    tests = t;
    emit();
  });
  final subAttendance = attendanceStream.listen((a) {
    attendance = a;
    emit();
  });
  final subSession = sessionStream.listen((s) {
    session = s;
    emit();
  });

  controller.onCancel = () {
    subStudents.cancel();
    subPayments.cancel();
    subTests.cancel();
    subAttendance.cancel();
    subSession.cancel();
  };

  return controller.stream;
}

Stream<List<DashboardStudentSummary>> _combineStudentSummaryStreams({
  required Stream<List<Student>> studentsStream,
  required Stream<List<Payment>> paymentsStream,
  required Stream<List<Test>> testsStream,
  required Stream<List<AttendanceData>> attendanceStream,
  required Stream<Map<int, double>> ministryHoursStream,
  required Stream<List<MissionPaymentScheduleData>> missionScheduleStream,
  required Stream<String?> sessionStream,
  Map<int?, String> classIdToName = const {},
  required List<(int, int)> effectivePeriod,
  required double monthlyTuition,
  required double sessionTuition,
}) {
  List<Student>? students;
  List<Payment>? payments;
  List<Test>? tests;
  List<AttendanceData>? attendance;
  Map<int, double>? ministryHours;
  List<MissionPaymentScheduleData>? missionSchedule;
  String? session;

  final controller = StreamController<List<DashboardStudentSummary>>();

  void emit() {
    if (students == null ||
        payments == null ||
        tests == null ||
        attendance == null ||
        ministryHours == null ||
        missionSchedule == null) {
      return;
    }
    final missionFundMap = {
      for (final r in missionSchedule!)
        r.studentId: r.amount > 0
            ? r.amount
            : r.mar +
                r.apr +
                r.may +
                r.jun +
                r.jul +
                r.aug +
                r.sep +
                r.oct,
    };
    final currentSession = (session?.trim().isEmpty ?? true)
        ? _defaultCurrentAcademicSession()
        : session!;
    controller.add(
      _computeStudentSummaries(
        students!,
        payments!,
        tests!,
        attendance!,
        ministryHours!,
        missionFundMap,
        currentSession,
        classIdToName,
        effectivePeriod,
        monthlyTuition,
        sessionTuition,
      ),
    );
  }

  final subStudents = studentsStream.listen((s) {
    students = s;
    emit();
  });
  final subPayments = paymentsStream.listen((p) {
    payments = p;
    emit();
  });
  final subTests = testsStream.listen((t) {
    tests = t;
    emit();
  });
  final subAttendance = attendanceStream.listen((a) {
    attendance = a;
    emit();
  });
  final subMinistry = ministryHoursStream.listen((m) {
    ministryHours = m;
    emit();
  });
  final subMission = missionScheduleStream.listen((m) {
    missionSchedule = m;
    emit();
  });
  final subSession = sessionStream.listen((s) {
    session = s;
    emit();
  });

  controller.onCancel = () {
    subStudents.cancel();
    subPayments.cancel();
    subTests.cancel();
    subAttendance.cancel();
    subMinistry.cancel();
    subMission.cancel();
    subSession.cancel();
  };

  return controller.stream;
}

List<DashboardCohortSummary> _computeCohortSummaries(
  List<Student> students,
  List<Payment> payments,
  List<Test> tests,
  List<AttendanceData> attendanceRecords,
  String currentSession,
  Map<int?, String> classIdToName,
  List<(int, int)> effectivePeriod,
  double monthlyTuition,
  double sessionTuition,
) {
  const passThreshold = AppConstants.passingTestScore;
  final sessionTrim = currentSession.trim();
  String className(int? id) => classIdToName[id] ?? '—';

  // Tests for current academic session only
  final testsForSession = tests
      .where(
        (t) =>
            (t.academicSession ?? '').trim() == sessionTrim &&
            t.subjectId != null,
      )
      .toList();

  // Group students by (classId, mode)
  final cohortKeys = <(int?, String)>[];
  final cohortStudents = <(int?, String), List<Student>>{};
  for (final s in students) {
    final classId = s.classId;
    final mode = s.mode ?? '—';
    final key = (classId, mode);
    if (!cohortStudents.containsKey(key)) {
      cohortKeys.add(key);
      cohortStudents[key] = [];
    }
    cohortStudents[key]!.add(s);
  }
  cohortKeys.sort((a, b) {
    final aName = className(a.$1);
    final bName = className(b.$1);
    final nameCmp = aName.compareTo(bName);
    if (nameCmp != 0) return nameCmp;
    return a.$2.compareTo(b.$2);
  });

  // Attendance: group by studentId, then compute % per student
  final attendanceByStudent = <int, List<AttendanceData>>{};
  for (final r in attendanceRecords) {
    attendanceByStudent.putIfAbsent(r.studentId, () => []).add(r);
  }

  final byStudentYear = <(int, int), Payment>{};
  for (final p in payments) {
    final y = int.tryParse(p.year);
    if (y != null) byStudentYear[(p.studentId, y)] = p;
  }
  final expectedPerMonth = monthlyTuition;

  final result = <DashboardCohortSummary>[];
  for (final key in cohortKeys) {
    final cohort = cohortStudents[key]!;
    final studentIds = cohort.map((s) => s.id).toSet();

    double totalBalance = 0.0;
    double balanceDueExpectedMonthly = 0.0;
    for (final student in cohort) {
      final totalPaid = totalSessionPaidForStudent(payments, student.id);
      final balance = sessionTuition - totalPaid;
      if (balance > 0) totalBalance += balance;

      double studentBalanceDueForPeriod = 0.0;
      for (final (y, m) in effectivePeriod) {
        final pYear = byStudentYear[(student.id, y)];
        final paid = pYear != null ? paymentAmountForMonth(pYear, y, m) : 0.0;
        studentBalanceDueForPeriod +=
            (expectedPerMonth - paid).clamp(0.0, double.infinity);
      }
      balanceDueExpectedMonthly += studentBalanceDueForPeriod;
    }

    // Cohort set: (subjectId, session) for this cohort in current session
    final cohortTestSet = <(int, String)>{
      for (final t in testsForSession)
        if (studentIds.contains(t.studentId))
          (t.subjectId!, (t.academicSession ?? '').trim()),
    };

    int cohortFailed = 0;
    int cohortPassed = 0;
    int cohortOutstanding = 0;
    for (final s in cohort) {
      final studentTestsForSession =
          testsForSession.where((t) => t.studentId == s.id).toList();
      final studentSet = <(int, String)>{
        for (final t in studentTestsForSession)
          (t.subjectId!, (t.academicSession ?? '').trim()),
      };
      final missing = cohortTestSet.difference(studentSet).length;
      final failed =
          studentTestsForSession.where((t) => t.score < passThreshold).length;
      final passed =
          studentTestsForSession.where((t) => t.score >= passThreshold).length;
      cohortFailed += failed;
      cohortPassed += passed;
      cohortOutstanding += missing;
    }

    double? avgAttendancePercent;
    final percentages = <double>[];
    for (final id in studentIds) {
      final records = attendanceByStudent[id];
      if (records == null || records.isEmpty) continue;
      final present = records.where((r) => r.present == 1).length;
      percentages.add((present / records.length) * 100);
    }
    if (percentages.isNotEmpty) {
      avgAttendancePercent =
          percentages.reduce((a, b) => a + b) / percentages.length;
    }

    result.add(
      DashboardCohortSummary(
        year: className(key.$1),
        mode: key.$2,
        studentCount: cohort.length,
        avgAttendancePercent: avgAttendancePercent,
        outstandingTests: cohortOutstanding,
        failedTests: cohortFailed,
        passedTests: cohortPassed,
        totalBalance: totalBalance,
        balanceDueExpectedMonthly: balanceDueExpectedMonthly,
      ),
    );
  }

  return result;
}

List<DashboardStudentSummary> _computeStudentSummaries(
  List<Student> students,
  List<Payment> payments,
  List<Test> tests,
  List<AttendanceData> attendanceRecords,
  Map<int, double> ministryHoursByStudent,
  Map<int, double> missionFundByStudent,
  String currentSession,
  Map<int?, String> classIdToName,
  List<(int, int)> effectivePeriod,
  double monthlyTuition,
  double sessionTuition,
) {
  final byStudentYear = <(int, int), Payment>{};
  for (final p in payments) {
    final y = int.tryParse(p.year);
    if (y != null) byStudentYear[(p.studentId, y)] = p;
  }
  final expectedPerMonth = monthlyTuition;
  const passThreshold = AppConstants.passingTestScore;
  final sessionTrim = currentSession.trim();
  String className(int? id) => classIdToName[id] ?? '—';

  // Tests for current academic session only (with subjectId for cohort set)
  final testsForSession = tests
      .where(
        (t) =>
            (t.academicSession ?? '').trim() == sessionTrim &&
            t.subjectId != null,
      )
      .toList();

  final attendanceByStudent = <int, List<AttendanceData>>{};
  for (final r in attendanceRecords) {
    attendanceByStudent.putIfAbsent(r.studentId, () => []).add(r);
  }

  final sorted = List<Student>.from(students)
    ..sort((a, b) {
      final surnameCmp = a.surname.compareTo(b.surname);
      if (surnameCmp != 0) return surnameCmp;
      return a.firstName.compareTo(b.firstName);
    });

  final result = <DashboardStudentSummary>[];
  for (final s in sorted) {
    final totalPaid = totalSessionPaidForStudent(payments, s.id);
    final balance = sessionTuition - totalPaid;
    final totalBalance = balance > 0 ? balance : 0.0;

    double balanceDueExpectedMonthly = 0.0;
    for (final (y, m) in effectivePeriod) {
      final pYear = byStudentYear[(s.id, y)];
      final paid = pYear != null ? paymentAmountForMonth(pYear, y, m) : 0.0;
      balanceDueExpectedMonthly +=
          (expectedPerMonth - paid).clamp(0.0, double.infinity);
    }

    double? avgAttendancePercent;
    final records = attendanceByStudent[s.id];
    if (records != null && records.isNotEmpty) {
      final present = records.where((r) => r.present == 1).length;
      avgAttendancePercent = (present / records.length) * 100;
    }

    final year = className(s.classId);
    final mode = s.mode ?? '—';
    final cohortIds = students
        .where((o) => o.classId == s.classId && (o.mode ?? '—') == mode)
        .map((o) => o.id)
        .toSet();
    final cohortTestSet = <(int, String)>{
      for (final t in testsForSession)
        if (cohortIds.contains(t.studentId))
          (t.subjectId!, (t.academicSession ?? '').trim()),
    };
    final studentTestsForSession =
        testsForSession.where((t) => t.studentId == s.id).toList();
    final studentSet = <(int, String)>{
      for (final t in studentTestsForSession)
        (t.subjectId!, (t.academicSession ?? '').trim()),
    };
    final missing = cohortTestSet.difference(studentSet).length;
    final failed =
        studentTestsForSession.where((t) => t.score < passThreshold).length;
    final passed =
        studentTestsForSession.where((t) => t.score >= passThreshold).length;
    final outstandingTests = missing;

    result.add(
      DashboardStudentSummary(
        studentId: s.id,
        displayName: '${s.surname}, ${s.firstName}',
        year: year,
        mode: mode,
        avgAttendancePercent: avgAttendancePercent,
        outstandingTests: outstandingTests,
        failedTests: failed,
        passedTests: passed,
        totalBalance: totalBalance,
        balanceDueExpectedMonthly: balanceDueExpectedMonthly,
        totalMinistryHours: ministryHoursByStudent[s.id] ?? 0.0,
        missionFund: missionFundByStudent[s.id] ?? 0.0,
      ),
    );
  }

  return result;
}
