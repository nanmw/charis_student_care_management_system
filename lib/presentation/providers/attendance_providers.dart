import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/attendance_repository.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return AttendanceRepository(db);
});

/// Stream of attendance rows for [date] (date-only). Scoped to facilitator's class when applicable.
final attendanceForDateProvider = StreamProvider.autoDispose
    .family<List<AttendanceData>, DateTime>((ref, date) {
  final repo = ref.watch(attendanceRepositoryProvider);
  final allowedIdsAsync = ref.watch(allowedStudentIdsStreamProvider);
  return allowedIdsAsync.when(
    data: (ids) => repo.watchAttendanceForDate(
      date,
      studentIds: ids.isEmpty ? null : ids,
    ),
    loading: () => Stream.value([]),
    error: (_, __) => Stream.value([]),
  );
});

/// Set of dates that have at least one attendance record.
/// [classFilter] when non-null (e.g. selected Class on Attendance screen): scope to that class only.
/// When null: admin sees all dates; facilitator sees only dates for their assigned students.
final datesWithAttendanceProvider = FutureProvider.autoDispose
    .family<Set<DateTime>, int?>((ref, classFilter) async {
  final repo = ref.watch(attendanceRepositoryProvider);
  final studentRepo = ref.watch(studentRepositoryProvider);

  if (classFilter != null) {
    final students = await studentRepo
        .watchStudents(statusFilter: 'Active', classIds: [classFilter])
        .first;
    final ids = students.map((s) => s.id).toList();
    return repo.getDatesWithAttendance(studentIds: ids);
  }

  final classIds = await ref.watch(currentUserAssignedClassIdsProvider.future);
  if (classIds == null) {
    return repo.getDatesWithAttendance(studentIds: null);
  }
  final ids = await ref.watch(allowedStudentIdsStreamProvider.future);
  return repo.getDatesWithAttendance(studentIds: ids);
});
