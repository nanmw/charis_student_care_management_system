import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/mission_location_repository.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';

final missionLocationRepositoryProvider = Provider<MissionLocationRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return MissionLocationRepository(
    db,
    onLocalChangeSetWritten: () =>
        ref.read(postCrudSyncSchedulerProvider).schedule(),
  );
});

/// Stream of all mission locations, ordered by name.
final missionLocationsStreamProvider =
    StreamProvider.autoDispose<List<MissionLocation>>((ref) {
  final repo = ref.watch(missionLocationRepositoryProvider);
  return repo.watchMissionLocations();
});
