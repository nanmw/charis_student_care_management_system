import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';

/// Assigned class ids for the current user when they are a facilitator; null for admins (no filter).
/// Empty list = facilitator with no assigned classes.
final currentUserAssignedClassIdsProvider =
    FutureProvider.autoDispose<List<int>?>((ref) async {
  final auth = await ref.watch(authStateProvider.future);
  if (auth is! Authenticated || auth.role != UserRole.facilitator) {
    return null;
  }
  final userId = int.tryParse(auth.user.id);
  if (userId == null) return <int>[];
  final repo = ref.watch(classRepositoryProvider);
  return repo.getClassIdsByFacilitatorUserId(userId);
});
