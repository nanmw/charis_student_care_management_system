import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/payment_repository.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return PaymentRepository(db);
});

/// Stream of payment rows for [year]. Scoped to facilitator's class when applicable (for dashboard/student summary view).
/// Payments management screen is admin-only and uses unscoped data when allowedStudentIds is empty.
final paymentsForYearStreamProvider =
    StreamProvider.autoDispose.family<List<Payment>, String>((ref, year) {
  final repo = ref.watch(paymentRepositoryProvider);
  final allowedIdsAsync = ref.watch(allowedStudentIdsStreamProvider);
  return allowedIdsAsync.when(
    data: (ids) => repo.watchPaymentsForYear(year, studentIds: ids.isEmpty ? null : ids),
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// Stream of payment rows for academic [sessionCode]. Uses session-based repository API.
/// Scoped to facilitator's students when allowedStudentIds is non-empty.
final paymentsForSessionStreamProvider =
    StreamProvider.autoDispose.family<List<Payment>, String>((ref, sessionCode) {
  final repo = ref.watch(paymentRepositoryProvider);
  final allowedIdsAsync = ref.watch(allowedStudentIdsStreamProvider);
  return allowedIdsAsync.when(
    data: (ids) => repo.watchPaymentsForSession(sessionCode, studentIds: ids.isEmpty ? null : ids),
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});
