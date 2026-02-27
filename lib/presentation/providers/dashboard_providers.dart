import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/change_sets_repository.dart';
import 'package:charis_student_care/presentation/providers/attendance_providers.dart';
import 'package:charis_student_care/presentation/providers/ministry_providers.dart';
import 'package:charis_student_care/presentation/providers/mission_payment_providers.dart';
import 'package:charis_student_care/presentation/providers/payment_providers.dart';
import 'package:charis_student_care/presentation/providers/academic_session_providers.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
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
  'jan': 'January',
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
  } catch (_) {}

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

String _defaultCurrentAcademicSession() {
  final now = DateTime.now();
  final year = now.year;
  return now.month >= 7 ? '$year-${year + 1}' : '${year - 1}-$year';
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
  final double totalMinistryHours;
  final double missionFund;

  String get yearModeLabel => '$year / $mode';
}

final changeSetsRepositoryProvider = Provider<ChangeSetsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ChangeSetsRepository(db);
});

/// Average attendance percentage for the last 30 days.
final averageAttendancePercentageProvider =
    StreamProvider.autoDispose<double?>((ref) {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.watchAverageAttendancePercentage(days: 30);
});

/// Total balance due across all active students for the current year. Scoped for facilitators.
final totalBalanceDueProvider = StreamProvider.autoDispose<double>((ref) {
  final paymentRepo = ref.watch(paymentRepositoryProvider);
  final studentRepo = ref.watch(studentRepositoryProvider);
  final classIdsAsync = ref.watch(currentUserAssignedClassIdsProvider);
  final currentYear = DateTime.now().year.toString();
  return classIdsAsync.when(
    data: (classIds) {
      final studentsStream = studentRepo.watchStudents(statusFilter: 'Active', classIds: classIds);
      return studentsStream.asyncExpand((students) {
        final ids = students.map((s) => s.id).toList();
        final payStream = paymentRepo.watchPaymentsForYear(
          currentYear,
          studentIds: ids.isEmpty ? null : ids,
        );
        return payStream.map((payments) {
          final paymentMap = {for (final p in payments) p.studentId: p};
          double totalBalance = 0.0;
          for (final student in students) {
            final payment = paymentMap[student.id];
            final totalPaid = payment != null
                ? (payment.jan +
                    payment.feb +
                    payment.mar +
                    payment.apr +
                    payment.may +
                    payment.jun +
                    payment.jul +
                    payment.aug +
                    payment.sep +
                    payment.oct +
                    payment.nov +
                    payment.dec +
                    payment.lumpSum)
                : 0.0;
            final balance = AppConstants.fullTuitionAmount - totalPaid;
            if (balance > 0) totalBalance += balance;
          }
          return totalBalance;
        });
      });
    },
    loading: () => Stream.value(0.0),
    error: (_, __) => Stream.value(0.0),
  );
});

/// Recent activities from change sets.
final recentActivitiesProvider =
    StreamProvider.autoDispose<List<ChangeSet>>((ref) {
  final repo = ref.watch(changeSetsRepositoryProvider);
  return repo.watchRecentChanges(limit: 10);
});

/// Recent activities enriched with parsed payload (student, user, screen, what changed).
final recentActivitiesEnrichedProvider =
    Provider.autoDispose<AsyncValue<List<DashboardActivity>>>((ref) {
  return ref.watch(recentActivitiesProvider).when(
        data: (list) =>
            AsyncValue.data(list.map(dashboardActivityFromChangeSet).toList()),
        loading: () => const AsyncValue.loading(),
        error: (e, st) => AsyncValue.error(e, st),
      );
});

/// Summary table rows by cohort (class + mode). Scoped for facilitators.
final dashboardCohortSummaryProvider =
    StreamProvider.autoDispose<List<DashboardCohortSummary>>((ref) {
  final studentRepo = ref.watch(studentRepositoryProvider);
  final paymentRepo = ref.watch(paymentRepositoryProvider);
  final attendanceRepo = ref.watch(attendanceRepositoryProvider);
  final testRepo = ref.watch(testRepositoryProvider);
  final sessionRepo = ref.watch(academicSessionRepositoryProvider);
  final classes = ref.watch(allClassesFutureProvider).valueOrNull ?? [];
  final classIdToName = {null: '—', for (final c in classes) c.id: c.name};
  final currentYear = DateTime.now().year.toString();
  const days = 30;
  final classIdsAsync = ref.watch(currentUserAssignedClassIdsProvider);
  final allowedIdsAsync = ref.watch(allowedStudentIdsStreamProvider);

  return classIdsAsync.when(
    data: (classIds) => allowedIdsAsync.when(
      data: (ids) {
        final studentsStream = studentRepo.watchStudents(statusFilter: 'Active', classIds: classIds);
        final paymentsStream = paymentRepo.watchPaymentsForYear(currentYear, studentIds: ids.isEmpty ? null : ids);
        final attendanceStream = attendanceRepo.watchAttendanceLastDays(days, studentIds: ids.isEmpty ? null : ids);
        return _combineDashboardStreams(
          studentsStream: studentsStream,
          paymentsStream: paymentsStream,
          testsStream: testRepo.watchAllTests(),
          attendanceStream: attendanceStream,
          sessionStream: sessionRepo.watchCurrentSession(),
          classIdToName: classIdToName,
          compute: _computeCohortSummaries,
        );
      },
      loading: () => Stream.value(<DashboardCohortSummary>[]),
      error: (_, __) => Stream.value(<DashboardCohortSummary>[]),
    ),
    loading: () => Stream.value(<DashboardCohortSummary>[]),
    error: (_, __) => Stream.value(<DashboardCohortSummary>[]),
  );
});

/// Summary table rows: one per student (filtered by [statusFilter]). Scoped for facilitators.
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
  final currentYear = DateTime.now().year.toString();
  const days = 30;
  final classIdsAsync = ref.watch(currentUserAssignedClassIdsProvider);
  final allowedIdsAsync = ref.watch(allowedStudentIdsStreamProvider);

  return classIdsAsync.when(
    data: (classIds) => allowedIdsAsync.when(
      data: (ids) {
        final studentsStream = studentRepo.watchStudents(statusFilter: statusFilter, classIds: classIds);
        final paymentsStream = paymentRepo.watchPaymentsForYear(currentYear, studentIds: ids.isEmpty ? null : ids);
        final attendanceStream = attendanceRepo.watchAttendanceLastDays(days, studentIds: ids.isEmpty ? null : ids);
        return _combineStudentSummaryStreams(
          studentsStream: studentsStream,
          paymentsStream: paymentsStream,
          testsStream: testRepo.watchAllTests(),
          attendanceStream: attendanceStream,
          ministryHoursStream: ministryRepo.watchTotalHoursByStudent(),
          missionScheduleStream: missionRepo.watchForYear(currentYear),
          sessionStream: sessionRepo.watchCurrentSession(),
          classIdToName: classIdToName,
        );
      },
      loading: () => Stream.value(<DashboardStudentSummary>[]),
      error: (_, __) => Stream.value(<DashboardStudentSummary>[]),
    ),
    loading: () => Stream.value(<DashboardStudentSummary>[]),
    error: (_, __) => Stream.value(<DashboardStudentSummary>[]),
  );
});

Stream<T> _combineDashboardStreams<T>({
  required Stream<List<Student>> studentsStream,
  required Stream<List<Payment>> paymentsStream,
  required Stream<List<Test>> testsStream,
  required Stream<List<AttendanceData>> attendanceStream,
  required Stream<String?> sessionStream,
  Map<int?, String> classIdToName = const {},
  required T Function(
    List<Student>,
    List<Payment>,
    List<Test>,
    List<AttendanceData>,
    String,
    Map<int?, String>,
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
      compute(students!, payments!, tests!, attendance!, currentSession, classIdToName),
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
        r.studentId:
            r.mar + r.apr + r.may + r.jun + r.jul + r.aug + r.sep + r.oct,
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
) {
  final paymentMap = {for (final p in payments) p.studentId: p};
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

  final result = <DashboardCohortSummary>[];
  for (final key in cohortKeys) {
    final cohort = cohortStudents[key]!;
    final studentIds = cohort.map((s) => s.id).toSet();

    double totalBalance = 0.0;
    for (final student in cohort) {
      final payment = paymentMap[student.id];
      final totalPaid = payment != null
          ? (payment.jan +
              payment.feb +
              payment.mar +
              payment.apr +
              payment.may +
              payment.jun +
              payment.jul +
              payment.aug +
              payment.sep +
              payment.oct +
              payment.nov +
              payment.dec +
              payment.lumpSum)
          : 0.0;
      final balance = AppConstants.fullTuitionAmount - totalPaid;
      if (balance > 0) totalBalance += balance;
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
) {
  final paymentMap = {for (final p in payments) p.studentId: p};
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
    final payment = paymentMap[s.id];
    final totalPaid = payment != null
        ? (payment.jan +
            payment.feb +
            payment.mar +
            payment.apr +
            payment.may +
            payment.jun +
            payment.jul +
            payment.aug +
            payment.sep +
            payment.oct +
            payment.nov +
            payment.dec +
            payment.lumpSum)
        : 0.0;
    final balance = AppConstants.fullTuitionAmount - totalPaid;
    final totalBalance = balance > 0 ? balance : 0.0;

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
        totalMinistryHours: ministryHoursByStudent[s.id] ?? 0.0,
        missionFund: missionFundByStudent[s.id] ?? 0.0,
      ),
    );
  }

  return result;
}
