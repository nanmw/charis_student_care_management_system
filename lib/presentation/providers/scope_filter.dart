import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';

/// Resolves the student-id filter for repository/provider queries.
///
/// - Admin / portfolio lead (`scope == null`): returns `null` (no filter).
/// - Facilitator with empty [FacilitatorScope.classIds]: returns `[]` (fail-closed).
/// - Facilitator with assigned classes: returns [allowedIds] when non-empty, else `[]`.
///
/// Callers must pass empty list (not null) when the filter should exclude all students.
List<int>? studentIdsFilterForScope(
  FacilitatorScope? scope,
  List<int> allowedIds,
) {
  if (scope == null) {
    // Admin / portfolio lead: unscoped.
    return allowedIds.isEmpty ? null : allowedIds;
  }
  // Facilitator: empty class assignment or empty allowed set => no students.
  if (scope.classIds == null || scope.classIds!.isEmpty) {
    return const [];
  }
  return allowedIds;
}
