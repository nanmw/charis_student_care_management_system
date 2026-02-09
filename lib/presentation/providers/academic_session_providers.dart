import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:charis_student_care/data/repositories/academic_session_repository.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

/// Provider for AcademicSessionRepository.
final academicSessionRepositoryProvider = Provider<AcademicSessionRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return AcademicSessionRepository(db);
});

/// Academic session options for dropdown (defaults + distinct from DB).
/// Global provider that any feature can use without depending on test_providers.
final academicSessionOptionsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final repo = ref.watch(academicSessionRepositoryProvider);
  return repo.getSessionOptions();
});

/// Current academic session (reactive stream).
/// Returns null if no current session is set.
/// Global provider that any feature can use without depending on test_providers.
final currentAcademicSessionProvider =
    StreamProvider.autoDispose<String?>((ref) {
  final repo = ref.watch(academicSessionRepositoryProvider);
  return repo.watchCurrentSession();
});
