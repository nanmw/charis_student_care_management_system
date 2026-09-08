import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/mission_payment_repository.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.test();
  });

  tearDown(() async {
    await db.close();
  });

  group('missionPaymentRowHasChanges', () {
    test('is false for missing row with all defaults', () {
      expect(
        missionPaymentRowHasChanges(
          edit: MissionPaymentData(),
          row: null,
        ),
        isFalse,
      );
    });

    test('treats null and empty trip/comment as equal', () {
      expect(
        missionPaymentRowHasChanges(
          edit: MissionPaymentData(tripSelected: '', comment: ''),
          row: null,
        ),
        isFalse,
      );
    });

    test('is true when a default row has an amount', () {
      expect(
        missionPaymentRowHasChanges(
          edit: MissionPaymentData(amount: 50),
          row: null,
        ),
        isTrue,
      );
    });
  });

  test('batch upsert notifies onLocalChangeSetWritten once for multiple rows',
      () async {
    var notifyCount = 0;
    final repo = MissionPaymentRepository(
      db,
      onLocalChangeSetWritten: () => notifyCount++,
    );

    final studentA = await db.into(db.students).insert(
          StudentsCompanion.insert(surname: 'Ada', firstName: 'Lovelace'),
        );
    final studentB = await db.into(db.students).insert(
          StudentsCompanion.insert(surname: 'Grace', firstName: 'Hopper'),
        );

    final count = await repo.batchUpsertMissionPayments(
      year: '2026',
      payments: {
        studentA: MissionPaymentData(amount: 100, mar: 10),
        studentB: MissionPaymentData(tripSelected: 'Cape Town', amount: 200),
      },
      userId: 'user-1',
      deviceId: 'test-device',
      userRole: UserRole.adminLevel01,
    );

    expect(count, 2);
    expect(notifyCount, 1);

    final changeSets = await db.select(db.changeSets).get();
    expect(
      changeSets.where((c) => c.table == 'mission_payment_schedule').length,
      2,
    );
  });
}
