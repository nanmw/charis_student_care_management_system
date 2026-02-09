import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/test_providers.dart';

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
    required this.recentTests,
  });

  final int totalTests;
  final int outstandingTests;
  final double averageScore;
  final int passedTests;
  final List<Test> recentTests;
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
/// [key] is (studentId, studentYear, studentMode). Outstanding = (subject, session) pairs
/// that the cohort (same year and mode) has sat for but this student has not.
final testSummaryForStudentProvider = StreamProvider.autoDispose
    .family<TestSummary, (int, String, String)>((ref, key) {
  final studentId = key.$1;
  final studentYear = key.$2;
  final studentMode = key.$3;
  final repo = ref.watch(testRepositoryProvider);
  ref.watch(studentsStreamProvider('Active'));
  ref.watch(allTestsProvider);

  return repo.watchTestsForStudent(studentId).map((tests) {
    final totalTests = tests.length;
    final passedTests = tests.where((t) => t.score >= AppConstants.passingTestScore).length;

    // Cohort = active students with same year and mode
    final students = ref.read(studentsStreamProvider('Active')).valueOrNull ?? [];
    final cohortIds = students
        .where((s) => s.year == studentYear && s.mode == studentMode)
        .map((s) => s.id)
        .toSet();

    // Cohort set: (subjectId, session) from all tests where student is in cohort; skip null subjectId
    final allTests = ref.read(allTestsProvider).valueOrNull ?? [];
    final cohortSet = <(int, String)>{
      for (final t in allTests)
        if (cohortIds.contains(t.studentId) && t.subjectId != null)
          (t.subjectId!, t.academicSession ?? ''),
    };

    // Student set: (subjectId, session) from this student's tests
    final studentSet = <(int, String)>{
      for (final t in tests)
        if (t.subjectId != null) (t.subjectId!, t.academicSession ?? ''),
    };

    final outstandingTests = cohortSet.difference(studentSet).length;

    double averageScore = 0.0;
    if (totalTests > 0) {
      final sum = tests.fold<int>(0, (sum, test) => sum + test.score);
      averageScore = sum / totalTests;
    }

    final recentTests = tests.take(10).toList();

    return TestSummary(
      totalTests: totalTests,
      outstandingTests: outstandingTests,
      averageScore: averageScore,
      passedTests: passedTests,
      recentTests: recentTests,
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
