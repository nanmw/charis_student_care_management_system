import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/ministry_providers.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/test_providers.dart';
import 'package:charis_student_care/presentation/providers/academic_session_providers.dart';

/// Attendance summary data model
class AttendanceSummary {
  AttendanceSummary({
    required this.totalDays,
    required this.presentDays,
    required this.percentage,
    required this.recentDates,
  });

  final int totalDays;
  final int presentDays;
  final double percentage;
  final List<DateTime> recentDates;
}

/// Test summary data model
class TestSummary {
  TestSummary({
    required this.totalTests,
    required this.outstandingTests,
    required this.averageScore,
    required this.passedTests,
    required this.passedTestsList,
    required this.failedTestsList,
    required this.outstandingItems,
  });

  final int totalTests;
  final int outstandingTests;
  final double averageScore;
  final int passedTests;
  final List<Test> passedTestsList;
  final List<Test> failedTestsList;
  final List<OutstandingTestItem> outstandingItems;
}

/// Outstanding test detail item for a specific academic session.
class OutstandingTestItem {
  OutstandingTestItem({
    required this.subjectId,
    required this.academicSession,
    required this.dateWhenOutstanding,
  });

  final int subjectId;
  final String academicSession;
  final DateTime dateWhenOutstanding;
}

String _defaultCurrentAcademicSession() {
  final now = DateTime.now();
  final year = now.year;
  return now.month >= 7 ? '$year-${year + 1}' : '${year - 1}-$year';
}

/// Payment summary data model
class PaymentSummary {
  PaymentSummary({
    required this.totalPaid,
    required this.balance,
    required this.paymentsByYear,
  });

  final double totalPaid;
  final double balance;
  final Map<String, Payment> paymentsByYear;
}

/// Provider for attendance summary for a specific student
final attendanceSummaryForStudentProvider = StreamProvider.autoDispose
    .family<AttendanceSummary, int>((ref, studentId) {
  final db = ref.watch(appDatabaseProvider);
  
  // Watch all attendance records for this student
  final query = db.select(db.attendance)
    ..where((t) => t.studentId.equals(studentId))
    ..orderBy([(t) => OrderingTerm.desc(t.date)]);
  
  return query.watch().map((allAttendance) {
    final totalDays = allAttendance.length;
    final presentDays = allAttendance.where((a) => a.present == 1).length;
    final percentage = totalDays > 0 ? (presentDays / totalDays) * 100 : 0.0;
    
    // Get recent dates (last 10)
    final recentDates = allAttendance
        .take(10)
        .map((a) => a.date)
        .toList();
    
    return AttendanceSummary(
      totalDays: totalDays,
      presentDays: presentDays,
      percentage: percentage,
      recentDates: recentDates,
    );
  });
});

/// Provider for test summary for a specific student.
/// [key] is (studentId, classId, studentMode). Outstanding = (subject, session) pairs
/// that the cohort (same class and mode) has sat for but this student has not.
final testSummaryForStudentProvider = StreamProvider.autoDispose
    .family<TestSummary, (int, int?, String)>((ref, key) {
  final studentId = key.$1;
  final classId = key.$2;
  final studentMode = key.$3;
  final repo = ref.watch(testRepositoryProvider);
  ref.watch(studentsStreamProvider('Active'));
  ref.watch(allTestsProvider);
  final currentSessionAsync = ref.watch(currentAcademicSessionProvider);

  return repo.watchTestsForStudent(studentId).map((tests) {
    final totalTests = tests.length;
    final passedTests =
        tests.where((t) => t.score >= AppConstants.passingTestScore).length;

    // Resolve current academic session (fallback to default if none set yet)
    final currentSession = currentSessionAsync.when(
      data: (value) {
        final trimmed = value?.trim();
        return (trimmed != null && trimmed.isNotEmpty)
            ? trimmed
            : _defaultCurrentAcademicSession();
      },
      loading: () => _defaultCurrentAcademicSession(),
      error: (_, __) => _defaultCurrentAcademicSession(),
    );

    // Cohort = active students with same class and mode
    final students =
        ref.read(studentsStreamProvider('Active')).valueOrNull ?? [];
    final cohortIds = students
        .where((s) => s.classId == classId && s.mode == studentMode)
        .map((s) => s.id)
        .toSet();

    // Filtered tests for current academic session (for detailed lists)
    final filteredStudentTests = tests
        .where(
          (t) => (t.academicSession ?? '').trim() == currentSession,
        )
        .toList();

    // Passed / failed lists for current academic session
    final passedTestsList = filteredStudentTests
        .where((t) => t.score >= AppConstants.passingTestScore)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final failedTestsList = filteredStudentTests
        .where((t) => t.score < AppConstants.passingTestScore)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    // Cohort tests for current academic session
    final allTests = ref.read(allTestsProvider).valueOrNull ?? [];
    final cohortTestsForSession = allTests.where((t) {
      if (!cohortIds.contains(t.studentId)) return false;
      if (t.subjectId == null) return false;
      return (t.academicSession ?? '').trim() == currentSession;
    }).toList();

    // Cohort set: (subjectId, session) for current academic session
    final cohortSet = <(int, String)>{
      for (final t in cohortTestsForSession)
        (t.subjectId!, (t.academicSession ?? '').trim()),
    };

    // Student set: (subjectId, session) from this student's tests for current session
    final studentSet = <(int, String)>{
      for (final t in filteredStudentTests)
        if (t.subjectId != null) (t.subjectId!, (t.academicSession ?? '').trim()),
    };

    final outstandingPairs = cohortSet.difference(studentSet);

    // Earliest date per (subjectId, session) in cohort (current session)
    final earliestByPair = <(int, String), DateTime>{};
    for (final t in cohortTestsForSession) {
      final key = (t.subjectId!, (t.academicSession ?? '').trim());
      final date = t.createdAt;
      final existing = earliestByPair[key];
      if (existing == null || date.isBefore(existing)) {
        earliestByPair[key] = date;
      }
    }

    final outstandingItems = <OutstandingTestItem>[
      for (final pair in outstandingPairs)
        if (earliestByPair[pair] != null)
          OutstandingTestItem(
            subjectId: pair.$1,
            academicSession: pair.$2,
            dateWhenOutstanding: earliestByPair[pair]!,
          ),
    ]..sort(
        (a, b) => b.dateWhenOutstanding.compareTo(a.dateWhenOutstanding),
      );

    final outstandingTests = outstandingItems.length;

    double averageScore = 0.0;
    if (totalTests > 0) {
      final sum = tests.fold<int>(0, (sum, test) => sum + test.score);
      averageScore = sum / totalTests;
    }

    return TestSummary(
      totalTests: totalTests,
      outstandingTests: outstandingTests,
      averageScore: averageScore,
      passedTests: passedTests,
      passedTestsList: passedTestsList,
      failedTestsList: failedTestsList,
      outstandingItems: outstandingItems,
    );
  });
});

/// Provider for payment summary for a specific student
final paymentSummaryForStudentProvider = StreamProvider.autoDispose
    .family<PaymentSummary, int>((ref, studentId) {
  final db = ref.watch(appDatabaseProvider);
  
  // Watch all payments for this student
  final query = db.select(db.payments)
    ..where((t) => t.studentId.equals(studentId))
    ..orderBy([(t) => OrderingTerm.desc(t.year)]);
  
  return query.watch().map((payments) {
    double totalPaid = 0.0;
    final paymentsByYear = <String, Payment>{};
    
    for (final payment in payments) {
      final yearTotal = payment.jan +
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
          payment.lumpSum;
      
      totalPaid += yearTotal;
      paymentsByYear[payment.year] = payment;
    }
    
    final balance = AppConstants.fullTuitionAmount - totalPaid;
    
    return PaymentSummary(
      totalPaid: totalPaid,
      balance: balance,
      paymentsByYear: paymentsByYear,
    );
  });
});

/// Provider for ministry entries list for a specific student (student summary Ministry tab).
final ministryEntriesForStudentProvider = StreamProvider.autoDispose
    .family<List<MinistryEntry>, int>((ref, studentId) {
  final repo = ref.watch(ministryEntryRepositoryProvider);
  return repo.watchMinistryEntriesForStudent(studentId);
});
