import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/attendance_repository.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return AttendanceRepository(db);
});

/// Stream of attendance rows for [date] (date-only). Use for reactive UI.
final attendanceForDateProvider = StreamProvider.autoDispose
    .family<List<AttendanceData>, DateTime>((ref, date) {
  final repo = ref.watch(attendanceRepositoryProvider);
  return repo.watchAttendanceForDate(date);
});
