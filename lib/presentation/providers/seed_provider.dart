import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/seed/first_year_full_time_students.dart';
import 'package:charis_student_care/data/seed/first_year_hybrid_students.dart';
import 'package:charis_student_care/data/seed/second_year_ft_students.dart';
import 'package:charis_student_care/data/seed/second_year_full_time_students.dart';
import 'package:charis_student_care/data/seed/third_year_ft_students.dart';
import 'package:charis_student_care/data/seed/third_year_hybrid_students.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

/// Runs once when first read. Seeds the 23 first-year full-time students if not already present.
/// Idempotent: skips if a student with surname 'Nsonga' (first of the 23) already exists.
final firstYearFullTimeSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  final classRepo = ref.read(classRepositoryProvider);
  final alreadySeeded = await repo.hasStudentWithSurname('Nsonga');
  if (alreadySeeded) return;

  final year1Class = await classRepo.getClassByName('Year 1');
  final classId = year1Class?.id;
  const mode = 'Full-time';
  const userRole = UserRole.adminLevel01;

  for (final s in firstYearFullTimeSeedStudents) {
    await repo.addStudent(
      s.surname,
      s.firstName,
      userRole: userRole,
      classId: classId,
      mode: mode,
    );
  }
});

/// Runs once when first read. Seeds the 34 first-year hybrid students if not already present.
/// Idempotent: skips if a student with surname 'Mafukidze' (first of the 34) already exists.
final firstYearHybridSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  final classRepo = ref.read(classRepositoryProvider);
  final alreadySeeded = await repo.hasStudentWithSurname('Mafukidze');
  if (alreadySeeded) return;

  final year1Class = await classRepo.getClassByName('Year 1');
  final classId = year1Class?.id;
  const mode = 'Hybrid';
  const userRole = UserRole.adminLevel01;

  for (final s in firstYearHybridSeedStudents) {
    await repo.addStudent(
      s.surname,
      s.firstName,
      userRole: userRole,
      classId: classId,
      mode: mode,
    );
  }
});

/// Runs once when first read. Seeds the 16 second-year full-time students if not already present.
/// Idempotent: skips if a student with surname 'Mazodze' (first of the 16) already exists.
final secondYearFtSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  final classRepo = ref.read(classRepositoryProvider);
  final alreadySeeded = await repo.hasStudentWithSurname('Mazodze');
  if (alreadySeeded) return;

  final year2Class = await classRepo.getClassByName('Year 2');
  final classId = year2Class?.id;
  const mode = 'Full-time';
  const userRole = UserRole.adminLevel01;

  for (final s in secondYearFtSeedStudents) {
    await repo.addStudent(
      s.surname,
      s.firstName,
      userRole: userRole,
      classId: classId,
      mode: mode,
    );
  }
});

/// Runs once when first read. Seeds the 15 third-year full-time students if not already present.
/// Idempotent: skips if a student with surname 'Bojabotsheha' (unique to this list) already exists.
final thirdYearFtSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  final classRepo = ref.read(classRepositoryProvider);
  final alreadySeeded = await repo.hasStudentWithSurname('Bojabotsheha');
  if (alreadySeeded) return;

  final year3Class = await classRepo.getClassByName('Year 3');
  final classId = year3Class?.id;
  const mode = 'Full-time';
  const userRole = UserRole.adminLevel01;

  for (final s in thirdYearFtSeedStudents) {
    await repo.addStudent(
      s.surname,
      s.firstName,
      userRole: userRole,
      classId: classId,
      mode: mode,
    );
  }
});

/// Runs once when first read. Seeds the 22 third-year hybrid students if not already present.
/// Idempotent: skips if a student with surname 'Takavingofa' (unique to this list) already exists.
final thirdYearHybridSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  final classRepo = ref.read(classRepositoryProvider);
  final alreadySeeded = await repo.hasStudentWithSurname('Takavingofa');
  if (alreadySeeded) return;

  final year3Class = await classRepo.getClassByName('Year 3');
  final classId = year3Class?.id;
  const mode = 'Hybrid';
  const userRole = UserRole.adminLevel01;

  for (final s in thirdYearHybridSeedStudents) {
    await repo.addStudent(
      s.surname,
      s.firstName,
      userRole: userRole,
      classId: classId,
      mode: mode,
    );
  }
});

/// Runs once when first read. Seeds the 23 second-year hybrid students if not already present.
/// Idempotent: skips if a student with surname 'Davids' (first of the 23) already exists.
final secondYearFullTimeSeedProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  final classRepo = ref.read(classRepositoryProvider);
  final alreadySeeded = await repo.hasStudentWithSurname('Davids');
  if (alreadySeeded) return;

  final year2Class = await classRepo.getClassByName('Year 2');
  final classId = year2Class?.id;
  const mode = 'Hybrid';
  const userRole = UserRole.adminLevel01;

  for (final s in secondYearFullTimeSeedStudents) {
    await repo.addStudent(
      s.surname,
      s.firstName,
      userRole: userRole,
      classId: classId,
      mode: mode,
    );
  }
});

/// One-time seed: if no users exist, create an initial admin user.
/// Password: set CHARIS_ADMIN_INITIAL_PASSWORD at build/run time; otherwise defaults to 'admin' (change after first login).
final seedFirstAdminProvider = FutureProvider<void>((ref) async {
  final repo = ref.read(userRepositoryProvider);
  final users = await repo.listUsers();
  if (users.isNotEmpty) return;
  const initialPassword = String.fromEnvironment(
    'CHARIS_ADMIN_INITIAL_PASSWORD',
    defaultValue: 'admin',
  );
  await repo.createUser(
    username: 'admin',
    plainPassword: initialPassword,
    displayName: 'Administrator',
    role: UserRole.adminLevel01,
  );
});

/// Default password for seeded facilitator users. Change after first login.
const _facilitatorSeedPassword = String.fromEnvironment(
  'CHARIS_FACILITATOR_INITIAL_PASSWORD',
  defaultValue: 'facilitator',
);

/// One-time seed: create one facilitator user per class (Year 1, Year 2, Year 3) with Full-time mode if not already present.
/// Scope is stored on Users (allowed_class_id, allowed_mode); no longer uses Classes.facilitator_user_id for scope.
final seedFacilitatorUsersProvider = FutureProvider<void>((ref) async {
  final userRepo = ref.read(userRepositoryProvider);

  final classRepo = ref.read(classRepositoryProvider);
  final year1 = await classRepo.getClassByName('Year 1');
  final year2 = await classRepo.getClassByName('Year 2');
  final year3 = await classRepo.getClassByName('Year 3');
  if (year1 == null || year2 == null || year3 == null) return;

  const defaultMode = 'Full-time';
  for (final entry in [
    ('facilitator_year1', 'Year 1 Facilitator', year1.id),
    ('facilitator_year2', 'Year 2 Facilitator', year2.id),
    ('facilitator_year3', 'Year 3 Facilitator', year3.id),
  ]) {
    final username = entry.$1;
    final displayName = entry.$2;
    final classId = entry.$3;
    final existing = await userRepo.findByUsername(username);
    if (existing != null) {
      await userRepo.updateUser(
        id: existing.id,
        allowedClassId: classId,
        allowedMode: defaultMode,
      );
      continue;
    }
    await userRepo.createUser(
      username: username,
      plainPassword: _facilitatorSeedPassword,
      displayName: displayName,
      role: UserRole.facilitator,
      allowedClassId: classId,
      allowedMode: defaultMode,
    );
  }
});
