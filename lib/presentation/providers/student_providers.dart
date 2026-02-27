import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/student_repository.dart';
import 'package:charis_student_care/data/repositories/user_repository.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final studentRepositoryProvider = Provider<StudentRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return StudentRepository(db);
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return UserRepository(db);
});

/// Stream of students ordered by surname. [statusFilter] default 'Active'; null = all.
/// Scoped to current user's assigned classes when they are a facilitator.
final studentsStreamProvider = StreamProvider.autoDispose
    .family<List<Student>, String?>((ref, statusFilter) {
  final repo = ref.watch(studentRepositoryProvider);
  final classIdsAsync = ref.watch(currentUserAssignedClassIdsProvider);
  return classIdsAsync.when(
    data: (classIds) =>
        repo.watchStudents(statusFilter: statusFilter, classIds: classIds),
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// Stream of students with class name resolved for display. Scoped for facilitators.
final studentsWithClassStreamProvider = StreamProvider.autoDispose
    .family<List<StudentWithClass>, String?>((ref, statusFilter) {
  final repo = ref.watch(studentRepositoryProvider);
  final classIdsAsync = ref.watch(currentUserAssignedClassIdsProvider);
  return classIdsAsync.when(
    data: (classIds) => repo.watchStudentsWithClass(
      statusFilter: statusFilter,
      classIds: classIds,
    ),
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// Stream of student ids in the current user's assigned classes (for facilitator scope).
/// When current user is admin, emits empty list (no filter applied elsewhere).
final allowedStudentIdsStreamProvider = StreamProvider.autoDispose<List<int>>((ref) {
  final classIdsAsync = ref.watch(currentUserAssignedClassIdsProvider);
  final repo = ref.watch(studentRepositoryProvider);
  return classIdsAsync.when(
    data: (classIds) {
      if (classIds == null || classIds.isEmpty) return Stream.value([]);
      return repo
          .watchStudents(statusFilter: 'Active', classIds: classIds)
          .map((students) => students.map((s) => s.id).toList());
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});
