import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/subject_repository.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

final subjectRepositoryProvider = Provider<SubjectRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SubjectRepository(db);
});

/// Stream of subjects for [year], ordered by name alphabetically.
final subjectsForYearStreamProvider =
    StreamProvider.autoDispose.family<List<Subject>, String>((ref, year) {
  final repo = ref.watch(subjectRepositoryProvider);
  return repo.watchSubjectsForYear(year);
});
