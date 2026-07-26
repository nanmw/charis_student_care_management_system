import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/repositories/class_repository.dart';
import 'package:charis_student_care/data/repositories/student_repository.dart';
import 'package:charis_student_care/data/repositories/user_repository.dart';
import 'package:charis_student_care/presentation/providers/database_provider.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';

export 'database_provider.dart' show appDatabaseProvider;

/// Shared repository and database providers. Used to avoid circular dependencies
/// (e.g. facilitator_scope_provider needs UserRepository without importing student_providers).

final classRepositoryProvider = Provider<ClassRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ClassRepository(
    db,
    onLocalChangeSetWritten: () =>
        ref.read(postCrudSyncSchedulerProvider).schedule(),
  );
});

final studentRepositoryProvider = Provider<StudentRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return StudentRepository(
    db,
    onLocalChangeSetWritten: () =>
        ref.read(postCrudSyncSchedulerProvider).schedule(),
  );
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return UserRepository(
    db,
    onLocalChangeSetWritten: () =>
        ref.read(postCrudSyncSchedulerProvider).schedule(),
  );
});
