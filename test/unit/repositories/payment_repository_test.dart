import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/payment_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.test();
  });

  tearDown(() async {
    await db.close();
  });

  test('batch upsert notifies onLocalChangeSetWritten once for multiple rows',
      () async {
    var notifyCount = 0;
    final repo = PaymentRepository(
      db,
      onLocalChangeSetWritten: () => notifyCount++,
    );

    final studentA = await db.into(db.students).insert(
          StudentsCompanion.insert(surname: 'Ada', firstName: 'Lovelace'),
        );
    final studentB = await db.into(db.students).insert(
          StudentsCompanion.insert(surname: 'Grace', firstName: 'Hopper'),
        );

    final count = await repo.batchUpsertPayments(
      year: '2026',
      payments: {
        studentA: PaymentData(mar: 10, lumpSum: 100),
        studentB: PaymentData(apr: 20),
      },
      userId: 'user-1',
      deviceId: 'test-device',
      userRole: UserRole.adminLevel01,
    );

    expect(count, 2);
    expect(notifyCount, 1);

    final changeSets = await db.select(db.changeSets).get();
    expect(changeSets.where((c) => c.table == 'payments').length, 2);
  });
}
