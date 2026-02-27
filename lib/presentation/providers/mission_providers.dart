import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/mission_repository.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

final missionRepositoryProvider = Provider<MissionRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final classRepo = ref.watch(classRepositoryProvider);
  return MissionRepository(db, classRepo);
});

/// Parameters for missions stream filter.
typedef MissionsStreamParams = ({String? year, bool activeOnly});

/// Stream of missions filtered by [year] and [activeOnly].
final missionsStreamProvider = StreamProvider.autoDispose
    .family<List<Mission>, MissionsStreamParams>((ref, params) {
  final repo = ref.watch(missionRepositoryProvider);
  return repo.watchMissions(
    year: params.year,
    activeOnly: params.activeOnly,
  );
});

/// Stream of all participation rows (for Student Participation table).
final missionParticipationsStreamProvider =
    StreamProvider.autoDispose<List<MissionParticipationRow>>((ref) {
  final repo = ref.watch(missionRepositoryProvider);
  return repo.watchAllParticipationRows();
});

/// Stream of participations for a single mission.
final participationsForMissionProvider = StreamProvider.autoDispose
    .family<List<MissionParticipation>, int>((ref, missionId) {
  final repo = ref.watch(missionRepositoryProvider);
  return repo.watchParticipationsForMission(missionId);
});

/// Students eligible for mission sign-up: Year 2 class, Active, and mode matches. Scoped for facilitators.
final studentsEligibleForMissionsProvider = StreamProvider.autoDispose
    .family<List<Student>, String>((ref, missionMode) async* {
  final classRepo = ref.watch(classRepositoryProvider);
  final studentRepo = ref.watch(studentRepositoryProvider);
  final classIds = await ref.watch(currentUserAssignedClassIdsProvider.future);
  final year2Class = await classRepo.getClassByName('Year 2');
  final year2ClassId = year2Class?.id;
  await for (final list
      in studentRepo.watchStudents(statusFilter: 'Active', classIds: classIds)) {
    yield list
        .where(
          (s) =>
              year2ClassId != null &&
              s.classId == year2ClassId &&
              (missionMode == 'Both' || s.mode == missionMode),
        )
        .toList();
  }
});
