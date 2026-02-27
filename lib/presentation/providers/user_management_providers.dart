import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

/// Stream of all users for the user management screen.
final usersStreamProvider = StreamProvider.autoDispose<List<User>>((ref) {
  final repo = ref.watch(userRepositoryProvider);
  return repo.watchUsers();
});
