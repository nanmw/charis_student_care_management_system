import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/student_repository.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/repository_providers.dart';

// Re-export so existing imports of student_providers still get these.
export 'repository_providers.dart' show appDatabaseProvider, studentRepositoryProvider, userRepositoryProvider;

/// Stream of students ordered by surname. [statusFilter] default 'Active'; null = all.
/// Scoped to current user's facilitator scope (class + mode when set).
final studentsStreamProvider = StreamProvider.autoDispose
    .family<List<Student>, String?>((ref, statusFilter) {
  final repo = ref.watch(studentRepositoryProvider);
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
  return scopeAsync.when(
    data: (scope) => repo.watchStudents(
      statusFilter: statusFilter,
      classIds: scope?.classIds,
      mode: scope?.mode,
    ),
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// Stream of students with class name resolved for display. Scoped for facilitators.
final studentsWithClassStreamProvider = StreamProvider.autoDispose
    .family<List<StudentWithClass>, String?>((ref, statusFilter) {
  final repo = ref.watch(studentRepositoryProvider);
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
  return scopeAsync.when(
    data: (scope) => repo.watchStudentsWithClass(
      statusFilter: statusFilter,
      classIds: scope?.classIds,
      mode: scope?.mode,
    ),
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// Stream of student ids in the current user's facilitator scope (for dashboard, student summary, etc.).
/// When current user is admin/portfolio lead, emits empty list (no filter applied elsewhere).
final allowedStudentIdsStreamProvider = StreamProvider.autoDispose<List<int>>((ref) {
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
  final repo = ref.watch(studentRepositoryProvider);
  return scopeAsync.when(
    data: (scope) {
      if (scope == null || scope.classIds == null || scope.classIds!.isEmpty) {
        return Stream.value([]);
      }
      return repo
          .watchStudents(
            statusFilter: 'Active',
            classIds: scope.classIds,
            mode: scope.mode,
          )
          .map((students) => students.map((s) => s.id).toList());
    },
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});
