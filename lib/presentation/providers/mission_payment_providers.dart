import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/mission_payment_repository.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

final missionPaymentRepositoryProvider =
    Provider<MissionPaymentRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return MissionPaymentRepository(db);
});

/// Stream of mission payment schedule rows for [year].
final missionPaymentsForYearStreamProvider = StreamProvider.autoDispose
    .family<List<MissionPaymentScheduleData>, String>((ref, year) {
  final repo = ref.watch(missionPaymentRepositoryProvider);
  return repo.watchForYear(year);
});
