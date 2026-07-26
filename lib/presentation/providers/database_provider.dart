import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';

/// Single app database instance for the provider scope.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  return AppDatabase();
});
