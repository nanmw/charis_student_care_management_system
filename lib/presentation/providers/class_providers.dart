import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/class_repository.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

final classRepositoryProvider = Provider<ClassRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return ClassRepository(db);
});

/// Stream of all classes ordered by sortOrder then name.
final allClassesStreamProvider =
    StreamProvider.autoDispose<List<SchoolClass>>((ref) {
  final repo = ref.watch(classRepositoryProvider);
  return repo.watchClasses();
});

/// One-time future of all classes.
final allClassesFutureProvider =
    FutureProvider.autoDispose<List<SchoolClass>>((ref) async {
  final repo = ref.watch(classRepositoryProvider);
  return repo.getAllClasses();
});

/// Classes visible to the current user: all classes for admins, only assigned classes for facilitators.
/// Use in student list class dropdown and any other "select class" UI.
final classesVisibleToCurrentUserProvider =
    FutureProvider.autoDispose<List<SchoolClass>>((ref) async {
  final auth = ref.watch(authStateProvider).valueOrNull;
  final repo = ref.watch(classRepositoryProvider);
  if (auth is! Authenticated || auth.role != UserRole.facilitator) {
    return repo.getAllClasses();
  }
  final userId = int.tryParse(auth.user.id);
  if (userId == null) return [];
  return repo.getClassesByFacilitatorUserId(userId);
});

/// Classes assigned to a given user (for user edit dialog).
final classesForFacilitatorUserIdProvider =
    FutureProvider.autoDispose.family<List<SchoolClass>, int>((ref, userId) {
  final repo = ref.watch(classRepositoryProvider);
  return repo.getClassesByFacilitatorUserId(userId);
});

/// Class by id (family).
final classByIdProvider =
    FutureProvider.autoDispose.family<SchoolClass?, int>((ref, id) async {
  final repo = ref.watch(classRepositoryProvider);
  return repo.getClassById(id);
});

/// Id of the "Year 1" class, or null if not found.
final year1ClassIdProvider = FutureProvider.autoDispose<int?>((ref) async {
  final classes = await ref.watch(allClassesFutureProvider.future);
  for (final c in classes) {
    if (c.name == 'Year 1') return c.id;
  }
  return null;
});

/// Id of the "Year 2" class, or null if not found (for mission eligibility).
final year2ClassIdProvider = FutureProvider.autoDispose<int?>((ref) async {
  final classes = await ref.watch(allClassesFutureProvider.future);
  for (final c in classes) {
    if (c.name == 'Year 2') return c.id;
  }
  return null;
});

/// Id of the "Year 3" class, or null if not found.
final year3ClassIdProvider = FutureProvider.autoDispose<int?>((ref) async {
  final classes = await ref.watch(allClassesFutureProvider.future);
  for (final c in classes) {
    if (c.name == 'Year 3') return c.id;
  }
  return null;
});
