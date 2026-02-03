import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/change_sets_repository.dart';
import 'package:charis_student_care/presentation/providers/attendance_providers.dart';
import 'package:charis_student_care/presentation/providers/payment_providers.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

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

/// Total balance due across all active students for the current year.
/// Calculates per-student balances and sums them reactively.
final totalBalanceDueProvider = StreamProvider.autoDispose<double>((ref) {
  final paymentRepo = ref.watch(paymentRepositoryProvider);
  final studentRepo = ref.watch(studentRepositoryProvider);
  final currentYear = DateTime.now().year.toString();
  final paymentsStream = paymentRepo.watchPaymentsForYear(currentYear);
  final studentsStream = studentRepo.watchStudents(statusFilter: 'Active');
  
  // Combine both streams reactively using asyncExpand
  return studentsStream.asyncExpand((students) {
    return paymentsStream.map((payments) {
      // Create a map of studentId -> payment for quick lookup
      final paymentMap = {for (final p in payments) p.studentId: p};
      
      // Calculate balance for each active student
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
        // Only add positive balances (students who owe money)
        if (balance > 0) {
          totalBalance += balance;
        }
      }
      
      return totalBalance;
    });
  });
});

/// Recent activities from change sets.
final recentActivitiesProvider =
    StreamProvider.autoDispose<List<ChangeSet>>((ref) {
  final repo = ref.watch(changeSetsRepositoryProvider);
  return repo.watchRecentChanges(limit: 10);
});
