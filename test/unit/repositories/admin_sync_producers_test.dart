import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/app_settings_repository.dart';
import 'package:charis_student_care/data/repositories/class_repository.dart';
import 'package:charis_student_care/data/repositories/user_repository.dart';
import 'package:drift/drift.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.test();
  });

  tearDown(() async {
    await db.close();
  });

  test('user create without sync metadata does not write change-set (seed path)',
      () async {
    final repo = UserRepository(db);
    await repo.createUser(
      username: 'seed_admin',
      plainPassword: 'secret',
      role: UserRole.adminLevel01,
      actorRole: UserRole.adminLevel01,
    );
    expect(await db.select(db.changeSets).get(), isEmpty);
  });

  test('user create with userId writes users change-set', () async {
    final repo = UserRepository(db);
    await repo.createUser(
      username: 'synced_user',
      plainPassword: 'secret',
      role: UserRole.facilitator,
      actorRole: UserRole.adminLevel01,
      userId: 'actor-1',
      deviceId: 'device-test',
    );
    final sets = await db.select(db.changeSets).get();
    expect(sets, hasLength(1));
    expect(sets.single.table, 'users');
    expect(sets.single.operation, 'INSERT');
    expect(sets.single.payload.contains('passwordHash'), isTrue);
    expect(sets.single.payload.contains('secret'), isFalse);
  });

  test('class insert with userId writes classes change-set', () async {
    final repo = ClassRepository(db);
    await repo.insert(
      ClassesCompanion.insert(name: 'Year 4', sortOrder: const Value(4)),
      userRole: UserRole.adminLevel01,
      userId: 'actor-1',
      deviceId: 'device-test',
    );
    final sets = await db.select(db.changeSets).get();
    expect(sets, hasLength(1));
    expect(sets.single.table, 'classes');
    expect(sets.single.payload.contains('Year 4'), isTrue);
  });

  test('app settings syncable keys write change-set; onedrive does not',
      () async {
    final repo = AppSettingsRepository(db);
    await repo.set(
      AppSettingsRepository.keyMonthlyTuitionFee,
      '2400',
      userRole: UserRole.adminLevel01,
      userId: 'actor-1',
      deviceId: 'device-test',
    );
    await repo.set(
      AppSettingsRepository.keyOnedriveUrl,
      'https://example.com',
      userId: 'actor-1',
      deviceId: 'device-test',
    );
    final sets = await db.select(db.changeSets).get();
    expect(sets, hasLength(1));
    expect(sets.single.recordId, AppSettingsRepository.keyMonthlyTuitionFee);
  });
}
