import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/test_repository.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

final testRepositoryProvider = Provider<TestRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return TestRepository(db);
});

/// Stream of tests for [studentId], newest first.
final testsForStudentProvider = StreamProvider.autoDispose
    .family<List<Test>, int>((ref, studentId) {
  final repo = ref.watch(testRepositoryProvider);
  return repo.watchTestsForStudent(studentId);
});

/// Total outstanding tests count (score < 70) across all students. Reactive.
final totalOutstandingCountProvider = StreamProvider.autoDispose<int>((ref) {
  final repo = ref.watch(testRepositoryProvider);
  return repo.watchTotalOutstandingCount();
});
