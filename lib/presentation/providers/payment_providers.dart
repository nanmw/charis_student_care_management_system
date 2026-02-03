import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/payment_repository.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return PaymentRepository(db);
});

/// Stream of payment rows for [year]. Use for reactive UI on payments screen.
final paymentsForYearStreamProvider =
    StreamProvider.autoDispose.family<List<Payment>, String>((ref, year) {
  final repo = ref.watch(paymentRepositoryProvider);
  return repo.watchPaymentsForYear(year);
});
