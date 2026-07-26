import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/payment_repository.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/scope_filter.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return PaymentRepository(
    db,
    onLocalChangeSetWritten: () =>
        ref.read(postCrudSyncSchedulerProvider).schedule(),
  );
});

/// Stream of payment rows for [year]. Scoped to facilitator's class when applicable.
final paymentsForYearStreamProvider =
    StreamProvider.autoDispose.family<List<Payment>, String>((ref, year) {
  final repo = ref.watch(paymentRepositoryProvider);
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
  final allowedIdsAsync = ref.watch(allowedStudentIdsStreamProvider);
  return scopeAsync.when(
    data: (scope) => allowedIdsAsync.when(
      data: (ids) {
        final filter = studentIdsFilterForScope(scope, ids);
        return repo.watchPaymentsForYear(year, studentIds: filter);
      },
      loading: () => const Stream.empty(),
      error: (e, st) => Stream.error(e, st),
    ),
    loading: () => const Stream.empty(),
    error: (e, st) => Stream.error(e, st),
  );
});

/// Stream of payment rows for academic [sessionCode]. Uses session-based repository API.
final paymentsForSessionStreamProvider =
    StreamProvider.autoDispose.family<List<Payment>, String>((ref, sessionCode) {
  final repo = ref.watch(paymentRepositoryProvider);
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
  final allowedIdsAsync = ref.watch(allowedStudentIdsStreamProvider);
  return scopeAsync.when(
    data: (scope) => allowedIdsAsync.when(
      data: (ids) {
        final filter = studentIdsFilterForScope(scope, ids);
        return repo.watchPaymentsForSession(sessionCode, studentIds: filter);
      },
      loading: () => const Stream.empty(),
      error: (e, st) => Stream.error(e, st),
    ),
    loading: () => const Stream.empty(),
    error: (e, st) => Stream.error(e, st),
  );
});
