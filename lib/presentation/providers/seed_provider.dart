import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/seed/first_year_full_time_students.dart';
import 'package:charis_student_care/data/seed/first_year_hybrid_students.dart';
import 'package:charis_student_care/data/seed/second_year_ft_students.dart';
import 'package:charis_student_care/data/seed/second_year_full_time_students.dart';
import 'package:charis_student_care/data/seed/third_year_ft_students.dart';
import 'package:charis_student_care/data/seed/third_year_hybrid_students.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

/// Runs once when first read. Seeds the 23 first-year full-time students if not already present.
/// Idempotent: skips if a student with surname 'Nsonga' (first of the 23) already exists.
final firstYearFullTimeSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  final alreadySeeded = await repo.hasStudentWithSurname('Nsonga');
  if (alreadySeeded) return;

  const year = 'Year 1';
  const mode = 'Full-time';
  const userRole = UserRole.adminLevel01;

  for (final s in firstYearFullTimeSeedStudents) {
    await repo.addStudent(
      s.surname,
      s.firstName,
      userRole: userRole,
      year: year,
      mode: mode,
    );
  }
});

/// Runs once when first read. Seeds the 34 first-year hybrid students if not already present.
/// Idempotent: skips if a student with surname 'Mafukidze' (first of the 34) already exists.
final firstYearHybridSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  final alreadySeeded = await repo.hasStudentWithSurname('Mafukidze');
  if (alreadySeeded) return;

  const year = 'Year 1';
  const mode = 'Hybrid';
  const userRole = UserRole.adminLevel01;

  for (final s in firstYearHybridSeedStudents) {
    await repo.addStudent(
      s.surname,
      s.firstName,
      userRole: userRole,
      year: year,
      mode: mode,
    );
  }
});

/// Runs once when first read. Seeds the 16 second-year full-time students if not already present.
/// Idempotent: skips if a student with surname 'Mazodze' (first of the 16) already exists.
final secondYearFtSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  final alreadySeeded = await repo.hasStudentWithSurname('Mazodze');
  if (alreadySeeded) return;

  const year = 'Year 2';
  const mode = 'Full-time';
  const userRole = UserRole.adminLevel01;

  for (final s in secondYearFtSeedStudents) {
    await repo.addStudent(
      s.surname,
      s.firstName,
      userRole: userRole,
      year: year,
      mode: mode,
    );
  }
});

/// Runs once when first read. Seeds the 15 third-year full-time students if not already present.
/// Idempotent: skips if a student with surname 'Bojabotsheha' (unique to this list) already exists.
final thirdYearFtSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  final alreadySeeded = await repo.hasStudentWithSurname('Bojabotsheha');
  if (alreadySeeded) return;

  const year = 'Year 3';
  const mode = 'Full-time';
  const userRole = UserRole.adminLevel01;

  for (final s in thirdYearFtSeedStudents) {
    await repo.addStudent(
      s.surname,
      s.firstName,
      userRole: userRole,
      year: year,
      mode: mode,
    );
  }
});

/// Runs once when first read. Seeds the 22 third-year hybrid students if not already present.
/// Idempotent: skips if a student with surname 'Takavingofa' (unique to this list) already exists.
final thirdYearHybridSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  final alreadySeeded = await repo.hasStudentWithSurname('Takavingofa');
  if (alreadySeeded) return;

  const year = 'Year 3';
  const mode = 'Hybrid';
  const userRole = UserRole.adminLevel01;

  for (final s in thirdYearHybridSeedStudents) {
    await repo.addStudent(
      s.surname,
      s.firstName,
      userRole: userRole,
      year: year,
      mode: mode,
    );
  }
});

/// Runs once when first read. Seeds the 23 second-year hybrid students if not already present.
/// Idempotent: skips if a student with surname 'Davids' (first of the 23) already exists.
final secondYearFullTimeSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  final alreadySeeded = await repo.hasStudentWithSurname('Davids');
  if (alreadySeeded) return;

  const year = 'Year 2';
  const mode = 'Hybrid';
  const userRole = UserRole.adminLevel01;

  for (final s in secondYearFullTimeSeedStudents) {
    await repo.addStudent(
      s.surname,
      s.firstName,
      userRole: userRole,
      year: year,
      mode: mode,
    );
  }
});
