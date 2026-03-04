import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/class_repository.dart';
import 'package:charis_student_care/data/repositories/student_repository.dart';
import 'package:charis_student_care/data/repositories/user_repository.dart';

/// Shared repository and database providers. Used to avoid circular dependencies
/// (e.g. facilitator_scope_provider needs UserRepository without importing student_providers).
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});

final classRepositoryProvider = Provider<ClassRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ClassRepository(db);
});

final studentRepositoryProvider = Provider<StudentRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return StudentRepository(db);
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return UserRepository(db);
});
