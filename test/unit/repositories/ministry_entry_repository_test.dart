import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/ministry_entry_repository.dart';

void main() {
  late AppDatabase db;
  late MinistryEntryRepository repo;
  var notifyCount = 0;

  setUp(() async {
    db = AppDatabase.test();
    notifyCount = 0;
    repo = MinistryEntryRepository(
      db,
      onLocalChangeSetWritten: () => notifyCount++,
    );
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertStudent(String surname, String firstName) {
    return db.into(db.students).insert(
          StudentsCompanion.insert(surname: surname, firstName: firstName),
        );
  }

  MinistryEntriesCompanion companionFor(
    int studentId, {
    double hours = 2.0,
    DateTime? date,
    String ministryType = 'Evangelism',
  }) {
    return MinistryEntriesCompanion(
      studentId: Value(studentId),
      year: const Value('2026'),
      term: const Value(1),
      ministryType: Value(ministryType),
      date: Value(date ?? DateTime(2026, 3, 1)),
      hours: Value(hours),
    );
  }

  test('insert writes one row, one change-set, and notifies once', () async {
    final studentId = await insertStudent('Ada', 'Lovelace');

    final id = await repo.insert(
      companionFor(studentId),
      userRole: UserRole.facilitator,
      userId: 'user-1',
      deviceId: 'test-device',
      screen: 'Ministry Hours',
    );

    expect(id, greaterThan(0));
    expect(notifyCount, 1);

    final entries = await db.select(db.ministryEntries).get();
    expect(entries, hasLength(1));
    expect(entries.single.studentId, studentId);
    expect(entries.single.hours, 2.0);

    final changeSets = await db.select(db.changeSets).get();
    expect(changeSets, hasLength(1));
    expect(changeSets.single.table, 'ministry_entries');
    expect(changeSets.single.operation, 'INSERT');
    expect(changeSets.single.recordId, id.toString());
    final payload =
        jsonDecode(changeSets.single.payload) as Map<String, dynamic>;
    expect(payload['studentId'], studentId);
    expect(payload['ministryType'], 'Evangelism');
    expect(payload['hours'], 2.0);
    expect(payload['screen'], 'Ministry Hours');
  });

  test('insertAll creates N rows and N change-sets and notifies once',
      () async {
    final studentA = await insertStudent('Ada', 'Lovelace');
    final studentB = await insertStudent('Grace', 'Hopper');

    final count = await repo.insertAll(
      [
        companionFor(studentA, hours: 2.0),
        companionFor(studentB, hours: 3.5),
      ],
      userRole: UserRole.facilitator,
      userId: 'user-1',
      deviceId: 'test-device',
      screen: 'Ministry Hours',
    );

    expect(count, 2);
    expect(notifyCount, 1);

    final entries = await db.select(db.ministryEntries).get();
    expect(entries, hasLength(2));
    expect(
      entries.map((e) => e.studentId).toSet(),
      {studentA, studentB},
    );

    final changeSets = await db.select(db.changeSets).get();
    expect(changeSets.where((c) => c.table == 'ministry_entries').length, 2);
    expect(
      changeSets.every((c) => c.operation == 'INSERT'),
      isTrue,
    );
  });

  test('insertAll with empty list is a no-op', () async {
    final count = await repo.insertAll(
      const [],
      userRole: UserRole.facilitator,
      userId: 'user-1',
      deviceId: 'test-device',
    );

    expect(count, 0);
    expect(notifyCount, 0);
    expect(await db.select(db.ministryEntries).get(), isEmpty);
    expect(await db.select(db.changeSets).get(), isEmpty);
  });

  test('insertAll rolls back if one companion fails', () async {
    final studentA = await insertStudent('Ada', 'Lovelace');
    final studentB = await insertStudent('Grace', 'Hopper');
    final invalid = MinistryEntriesCompanion(
      studentId: Value(studentB),
      year: const Value('2026'),
      term: const Value(1),
      ministryType: const Value('Evangelism'),
      date: Value(DateTime(2026, 3, 1)),
    );

    await expectLater(
      repo.insertAll(
        [
          companionFor(studentA),
          invalid,
        ],
        userRole: UserRole.facilitator,
        userId: 'user-1',
        deviceId: 'test-device',
      ),
      throwsA(isA<Object>()),
    );

    expect(await db.select(db.ministryEntries).get(), isEmpty);
    expect(await db.select(db.changeSets).get(), isEmpty);
    expect(notifyCount, 0);
  });

  test('findStudentsWithEntryOnDate returns matching student ids', () async {
    final studentA = await insertStudent('Ada', 'Lovelace');
    final studentB = await insertStudent('Grace', 'Hopper');
    final studentC = await insertStudent('Alan', 'Turing');
    final date = DateTime(2026, 3, 1);

    await repo.insert(
      companionFor(studentA, date: date, ministryType: 'Evangelism'),
      userRole: UserRole.facilitator,
    );
    await repo.insert(
      companionFor(
        studentB,
        date: DateTime(2026, 3, 1, 14, 30),
        ministryType: 'Evangelism',
      ),
      userRole: UserRole.facilitator,
    );
    await repo.insert(
      companionFor(studentC, date: date, ministryType: 'Teaching'),
      userRole: UserRole.facilitator,
    );
    await repo.insert(
      companionFor(
        studentA,
        date: DateTime(2026, 3, 2),
        ministryType: 'Evangelism',
      ),
      userRole: UserRole.facilitator,
    );

    final matches = await repo.findStudentsWithEntryOnDate(
      studentIds: [studentA, studentB, studentC],
      date: date,
      ministryType: 'Evangelism',
    );

    expect(matches, [studentA, studentB]);
  });

  test('findStudentsWithEntryOnDate returns empty for empty student list',
      () async {
    final matches = await repo.findStudentsWithEntryOnDate(
      studentIds: const [],
      date: DateTime(2026, 3, 1),
      ministryType: 'Evangelism',
    );
    expect(matches, isEmpty);
  });
}
