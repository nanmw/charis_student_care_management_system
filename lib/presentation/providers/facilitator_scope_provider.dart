import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/repository_providers.dart';

/// Scope for a facilitator: optional list of class ids and optional mode filter.
/// When both [classIds] and [mode] are set, data is restricted to that class + mode.
/// When only [classIds] is set (legacy), data is restricted to those classes only.
/// Null scope = admin or portfolio lead (no filter).
class FacilitatorScope {
  const FacilitatorScope({this.classIds, this.mode});

  final List<int>? classIds;
  final String? mode;

  /// Whether this scope has a single class and mode (new model).
  bool get hasClassAndMode =>
      classIds != null && classIds!.isNotEmpty && mode != null && mode!.isNotEmpty;
}

/// Current user's facilitator scope: (classIds, mode) when role is facilitator; null otherwise.
/// For facilitators with allowed_class_id and allowed_mode set on Users, returns that single class + mode.
/// Legacy: facilitators without those set use class ids from Classes.facilitator_user_id (mode = null).
final currentUserFacilitatorScopeProvider =
    FutureProvider.autoDispose<FacilitatorScope?>((ref) async {
  final auth = await ref.watch(authStateProvider.future);
  if (auth is! Authenticated || auth.role != UserRole.facilitator) {
    return null;
  }
  final userId = int.tryParse(auth.user.id);
  if (userId == null) return const FacilitatorScope(classIds: [], mode: null);

  final userRepo = ref.watch(userRepositoryProvider);
  final user = await userRepo.getById(userId);
  if (user != null &&
      user.allowedClassId != null &&
      user.allowedMode != null &&
      user.allowedMode!.trim().isNotEmpty) {
    return FacilitatorScope(
      classIds: [user.allowedClassId!],
      mode: user.allowedMode!.trim(),
    );
  }

  // Legacy: scope from classes table
  final classRepo = ref.watch(classRepositoryProvider);
  final classIds = await classRepo.getClassIdsByFacilitatorUserId(userId);
  return FacilitatorScope(classIds: classIds.isEmpty ? null : classIds, mode: null);
});

/// Mode options the current user is allowed to see/select.
/// For facilitators with an assigned mode: single-element list (e.g. [scope.mode]).
/// For admins, portfolio leads, or legacy facilitators without mode: ['Full-time', 'Hybrid'].
final modeOptionsForCurrentUserProvider = Provider.autoDispose<List<String>>((ref) {
  final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
  return scopeAsync.when(
    data: (scope) {
      if (scope != null &&
          scope.mode != null &&
          scope.mode!.trim().isNotEmpty) {
        return [scope.mode!.trim()];
      }
      return const ['Full-time', 'Hybrid'];
    },
    loading: () => const ['Full-time', 'Hybrid'],
    error: (_, __) => const ['Full-time', 'Hybrid'],
  );
});

/// Assigned class ids for the current user when they are a facilitator; null for admins (no filter).
/// Empty list = facilitator with no assigned classes.
/// Prefer [currentUserFacilitatorScopeProvider] when you need mode as well.
final currentUserAssignedClassIdsProvider =
    FutureProvider.autoDispose<List<int>?>((ref) async {
  final scope = await ref.watch(currentUserFacilitatorScopeProvider.future);
  if (scope == null) return null;
  return scope.classIds ?? <int>[];
});
