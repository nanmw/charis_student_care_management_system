import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/change_sets_repository.dart';

void main() {
  late AppDatabase db;
  late ChangeSetsRepository repo;

  setUp(() async {
    db = AppDatabase.test();
    repo = ChangeSetsRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('ChangeSetsRepository', () {
    test('retagLegacyChangeSetsTo updates legacy device_id rows', () async {
      const legacyRowId = 'cs-legacy-test-1';
      await db.into(db.changeSets).insert(
            ChangeSetsCompanion.insert(
              id: legacyRowId,
              table: 'students',
              recordId: '1',
              operation: 'INSERT',
              payload: '{}',
              userId: 'user-a',
              version: 1,
              deviceId: 'legacy',
            ),
          );

      final updated = await repo.retagLegacyChangeSetsTo('device-local-uuid');
      expect(updated, 1);

      final row = await (db.select(db.changeSets)..where((t) => t.id.equals(legacyRowId)))
          .getSingle();
      expect(row.deviceId, 'device-local-uuid');

      final exportedScope = await repo.getChangeSetsByDevice('device-local-uuid');
      expect(exportedScope.map((e) => e.id).toList(), contains(legacyRowId));
    });

    test('retagLegacyChangeSetsTo returns 0 when no legacy rows', () async {
      final n = await repo.retagLegacyChangeSetsTo('any-id');
      expect(n, 0);
    });
  });
}
