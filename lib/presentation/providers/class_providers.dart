import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/repository_providers.dart';

export 'repository_providers.dart' show appDatabaseProvider, classRepositoryProvider;

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

/// Class name options for the Export & Reports screen. Admins/portfolio lead get all report class options; facilitators get only their assigned class(es).
final reportClassOptionsForCurrentUserProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final auth = ref.watch(authStateProvider).valueOrNull;
  if (auth is! Authenticated || auth.role != UserRole.facilitator) {
    return List<String>.from(AppConstants.reportClassOptions);
  }
  final classes = await ref.watch(classesVisibleToCurrentUserProvider.future);
  return classes.map((c) => c.name).toList();
});

/// Classes visible to the current user: all classes for admins/portfolio lead, only assigned class for facilitators.
/// Use in student list class dropdown and any other "select class" UI.
final classesVisibleToCurrentUserProvider =
    FutureProvider.autoDispose<List<SchoolClass>>((ref) async {
  final auth = ref.watch(authStateProvider).valueOrNull;
  final repo = ref.watch(classRepositoryProvider);
  if (auth is! Authenticated || auth.role != UserRole.facilitator) {
    return repo.getAllClasses();
  }
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  if (scope == null || scope.classIds == null || scope.classIds!.isEmpty) {
    return [];
  }
  // When scope has class ids (one or legacy multiple), resolve to SchoolClass list.
  final classes = <SchoolClass>[];
  for (final id in scope.classIds!) {
    final c = await repo.getClassById(id);
    if (c != null) classes.add(c);
  }
  return classes;
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
