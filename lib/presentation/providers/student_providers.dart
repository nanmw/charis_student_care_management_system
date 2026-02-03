import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/student_repository.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final studentRepositoryProvider = Provider<StudentRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return StudentRepository(db);
});

/// Stream of students ordered by surname. [statusFilter] default 'Active'; null = all.
final studentsStreamProvider =
    StreamProvider.autoDispose.family<List<Student>, String?>((ref, statusFilter) {
  final repo = ref.watch(studentRepositoryProvider);
  return repo.watchStudents(statusFilter: statusFilter);
});
