import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/subject_repository.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';

final subjectRepositoryProvider = Provider<SubjectRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SubjectRepository(
    db,
    onLocalChangeSetWritten: () =>
        ref.read(postCrudSyncSchedulerProvider).schedule(),
  );
});

/// Stream of subjects for [classId], ordered by curriculum sort order.
final subjectsForClassStreamProvider =
    StreamProvider.autoDispose.family<List<Subject>, int>((ref, classId) {
  final repo = ref.watch(subjectRepositoryProvider);
  return repo.watchSubjectsForClass(classId);
});
