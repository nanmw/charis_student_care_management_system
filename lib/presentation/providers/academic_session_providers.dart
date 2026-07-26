import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:charis_student_care/data/repositories/academic_session_repository.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';

/// Provider for AcademicSessionRepository.
final academicSessionRepositoryProvider = Provider<AcademicSessionRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return AcademicSessionRepository(
    db,
    onLocalChangeSetWritten: () =>
        ref.read(postCrudSyncSchedulerProvider).schedule(),
  );
});

/// Academic session options for dropdown (from DB only; optional suggested default when empty).
final academicSessionOptionsProvider =
    FutureProvider.autoDispose<List<String>>((ref) async {
  final repo = ref.watch(academicSessionRepositoryProvider);
  return repo.getSessionOptions();
});

/// Stream of all academic sessions (for Settings list and set-current dropdown).
final allAcademicSessionsStreamProvider =
    StreamProvider.autoDispose<List<AcademicSessionRecord>>((ref) {
  final repo = ref.watch(academicSessionRepositoryProvider);
  return repo.watchAllSessions();
});

/// Current academic session (reactive stream).
/// Returns null if no current session is set.
final currentAcademicSessionProvider =
    StreamProvider.autoDispose<String?>((ref) {
  final repo = ref.watch(academicSessionRepositoryProvider);
  return repo.watchCurrentSession();
});
