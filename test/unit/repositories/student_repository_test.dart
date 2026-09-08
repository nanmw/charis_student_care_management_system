import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/student_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.test();
  });

  tearDown(() async {
    await db.close();
  });

  test('importStudentsBatch notifies onLocalChangeSetWritten once for two students',
      () async {
    var notifyCount = 0;
    final repo = StudentRepository(
      db,
      onLocalChangeSetWritten: () => notifyCount++,
    );

    final count = await repo.importStudentsBatch(
      items: const [
        StudentBatchImportItem(surname: 'Ada', firstName: 'Lovelace'),
        StudentBatchImportItem(surname: 'Grace', firstName: 'Hopper'),
      ],
      userRole: UserRole.adminLevel01,
      userId: 'user-1',
      deviceId: 'test-device',
    );

    expect(count, 2);
    expect(notifyCount, 1);

    final changeSets = await db.select(db.changeSets).get();
    expect(changeSets.where((c) => c.table == 'students').length, 2);
  });

  test('importStudentsBatch does not notify when import fails', () async {
    var notifyCount = 0;
    final repo = StudentRepository(
      db,
      onLocalChangeSetWritten: () => notifyCount++,
    );

    await expectLater(
      repo.importStudentsBatch(
        items: const [
          StudentBatchImportItem(surname: 'Ada', firstName: 'Lovelace'),
          StudentBatchImportItem(surname: 'Grace', firstName: 'Hopper'),
        ],
        userRole: UserRole.facilitator,
        userId: 'user-1',
        deviceId: 'test-device',
      ),
      throwsA(isA<StateError>()),
    );

    expect(notifyCount, 0);
    final students = await db.select(db.students).get();
    expect(students, isEmpty);
  });
}
