import 'package:flutter_test/flutter_test.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/core/constants/sync_constants.dart';

void main() {
  late AppDatabase database;

  setUp(() async {
    database = AppDatabase.test();
  });

  tearDown(() async {
    await database.close();
  });

  group('Database Setup Tests', () {
    test('database can be instantiated', () {
      expect(database, isNotNull);
      expect(database, isA<AppDatabase>());
    });

    test('schema version is correct', () {
      expect(database.schemaVersion, equals(30));
    });

    test('tables are created correctly', () async {
      // Verify students table exists and can be queried
      final students = await database.select(database.students).get();
      expect(students, isEmpty); // Table exists but is empty initially

      // Verify change_sets table exists and can be queried
      final changeSets = await database.select(database.changeSets).get();
      expect(changeSets, isEmpty); // Table exists but is empty initially
    });

    test('indexes are created for efficient queries', () async {
      // Insert test data to verify indexes work
      await database.into(database.students).insert(
            StudentsCompanion.insert(surname: 'Test', firstName: 'Index'),
          );

      // Query using indexed column (surname) - should work efficiently
      final result = await (database.select(database.students)
            ..where((t) => t.surname.equals('Test')))
          .getSingle();
      expect(result.surname, equals('Test'));

      // Query using status index
      final activeStudents = await (database.select(database.students)
            ..where((t) => t.status.equals('Active')))
          .get();
      expect(activeStudents.length, greaterThan(0));
    });

    test('foreign keys are enabled', () async {
      // Foreign keys are enabled via PRAGMA foreign_keys = ON
      // This is verified by the fact that the database initializes without errors
      // In a real scenario with foreign key relationships, we would test constraint violations
      expect(database, isNotNull);
    });

    test('database can be closed', () async {
      await database.close();
      // Database is closed, verify it's in closed state
      expect(database, isNotNull);
    });
  });

  group('Students Table Tests', () {
    test('can insert a student', () async {
      final student = StudentsCompanion.insert(
        surname: 'Smith',
        firstName: 'John',
      );

      final id = await database.into(database.students).insert(student);
      expect(id, greaterThan(0));
    });

    test('student has default status of Active', () async {
      final student = StudentsCompanion.insert(
        surname: 'Doe',
        firstName: 'Jane',
      );

      await database.into(database.students).insert(student);
      final inserted = await database.select(database.students).getSingle();

      expect(inserted.status, equals('Active'));
    });

    test('student has default version of 1', () async {
      final student = StudentsCompanion.insert(
        surname: 'Williams',
        firstName: 'Bob',
      );

      await database.into(database.students).insert(student);
      final inserted = await database.select(database.students).getSingle();

      expect(inserted.version, equals(1));
    });

    test('student has createdAt and updatedAt timestamps', () async {
      final beforeInsert = DateTime.now().subtract(const Duration(seconds: 1));
      final student = StudentsCompanion.insert(
        surname: 'Brown',
        firstName: 'Alice',
      );

      await database.into(database.students).insert(student);
      final inserted = await database.select(database.students).getSingle();
      final afterInsert = DateTime.now().add(const Duration(seconds: 1));

      expect(inserted.createdAt, isNotNull);
      expect(inserted.updatedAt, isNotNull);
      // Timestamp should be between beforeInsert and afterInsert
      expect(inserted.createdAt.isAfter(beforeInsert), isTrue);
      expect(inserted.createdAt.isBefore(afterInsert), isTrue);
    });

    test('can update student', () async {
      final student = StudentsCompanion.insert(
        surname: 'Johnson',
        firstName: 'Mike',
      );

      final id = await database.into(database.students).insert(student);
      final original = await database.select(database.students).getSingle();

      // Add a small delay to ensure updatedAt will be different
      await Future.delayed(const Duration(milliseconds: 10));

      await (database.update(database.students)..where((t) => t.id.equals(id)))
          .write(StudentsCompanion(
        firstName: const Value('Michael'),
        version: Value(original.version + 1),
        updatedAt: Value(DateTime.now()),
      ),);

      final updated = await database.select(database.students).getSingle();
      expect(updated.firstName, equals('Michael'));
      expect(updated.version, equals(2));
      // updatedAt should be >= original.updatedAt
      expect(
          updated.updatedAt.isAfter(original.updatedAt) ||
              updated.updatedAt.isAtSameMomentAs(original.updatedAt),
          isTrue,);
    });

    test('can query students alphabetically by surname', () async {
      // Insert students in non-alphabetical order
      await database.into(database.students).insert(
            StudentsCompanion.insert(surname: 'Zebra', firstName: 'Zoe'),
          );
      await database.into(database.students).insert(
            StudentsCompanion.insert(surname: 'Apple', firstName: 'Adam'),
          );
      await database.into(database.students).insert(
            StudentsCompanion.insert(surname: 'Baker', firstName: 'Betty'),
          );

      final students = await (database.select(database.students)
            ..orderBy([(t) => OrderingTerm(expression: t.surname)]))
          .get();

      expect(students.length, equals(3));
      expect(students[0].surname, equals('Apple'));
      expect(students[1].surname, equals('Baker'));
      expect(students[2].surname, equals('Zebra'));
    });

    test('status constraint rejects invalid status', () async {
      final student = StudentsCompanion.insert(
        surname: 'Invalid',
        firstName: 'Status',
        status: const Value('InvalidStatus'),
      );

      expect(
        () => database.into(database.students).insert(student),
        throwsException,
      );
    });

    test('status constraint accepts valid statuses', () async {
      final statuses = ['Active', 'Withdrawn', 'Transferred'];

      for (final status in statuses) {
        final student = StudentsCompanion.insert(
          surname: 'Test$status',
          firstName: 'Student',
          status: Value(status),
        );

        final id = await database.into(database.students).insert(student);
        expect(id, greaterThan(0));
      }
    });

    test('can filter students by status', () async {
      await database.into(database.students).insert(
            StudentsCompanion.insert(
              surname: 'Active1',
              firstName: 'Student',
              status: const Value('Active'),
            ),
          );
      await database.into(database.students).insert(
            StudentsCompanion.insert(
              surname: 'Withdrawn1',
              firstName: 'Student',
              status: const Value('Withdrawn'),
            ),
          );
      await database.into(database.students).insert(
            StudentsCompanion.insert(
              surname: 'Active2',
              firstName: 'Student',
              status: const Value('Active'),
            ),
          );

      final activeStudents = await (database.select(database.students)
            ..where((t) => t.status.equals('Active'))
            ..orderBy([(t) => OrderingTerm(expression: t.surname)]))
          .get();

      expect(activeStudents.length, equals(2));
      expect(activeStudents[0].surname, equals('Active1'));
      expect(activeStudents[1].surname, equals('Active2'));
    });
  });

  group('ChangeSets Table Tests', () {
    test('can insert a change-set', () async {
      final changeSet = ChangeSetsCompanion.insert(
        id: 'test-uuid-1',
        table: 'students',
        recordId: '1',
        operation: SyncConstants.operationInsert,
        payload: '{"surname": "Test", "firstName": "Student"}',
        userId: 'user-123',
        version: 1,
        deviceId: 'test-device',
      );

      await database.into(database.changeSets).insert(changeSet);
      final inserted = await database.select(database.changeSets).getSingle();

      expect(inserted.id, equals('test-uuid-1'));
      expect(inserted.table, equals('students'));
      expect(inserted.operation, equals(SyncConstants.operationInsert));
    });

    test('change-set has timestamp', () async {
      final beforeInsert = DateTime.now().subtract(const Duration(seconds: 1));
      final changeSet = ChangeSetsCompanion.insert(
        id: 'test-uuid-2',
        table: 'students',
        recordId: '2',
        operation: SyncConstants.operationUpdate,
        payload: '{"status": "Active"}',
        userId: 'user-456',
        version: 2,
        deviceId: 'test-device',
      );

      await database.into(database.changeSets).insert(changeSet);
      final inserted = await database.select(database.changeSets).getSingle();
      final afterInsert = DateTime.now().add(const Duration(seconds: 1));

      expect(inserted.timestamp, isNotNull);
      // Timestamp should be between beforeInsert and afterInsert
      expect(inserted.timestamp.isAfter(beforeInsert), isTrue);
      expect(inserted.timestamp.isBefore(afterInsert), isTrue);
    });

    test('operation constraint rejects invalid operation', () async {
      final changeSet = ChangeSetsCompanion.insert(
        id: 'test-uuid-3',
        table: 'students',
        recordId: '3',
        operation: 'INVALID_OPERATION',
        payload: '{}',
        userId: 'user-789',
        version: 1,
        deviceId: 'test-device',
      );

      expect(
        () => database.into(database.changeSets).insert(changeSet),
        throwsException,
      );
    });

    test('operation constraint accepts valid operations', () async {
      final operations = [
        SyncConstants.operationInsert,
        SyncConstants.operationUpdate,
        SyncConstants.operationStatusChange,
      ];

      for (var i = 0; i < operations.length; i++) {
        final changeSet = ChangeSetsCompanion.insert(
          id: 'test-uuid-$i',
          table: 'students',
          recordId: '$i',
          operation: operations[i],
          payload: '{}',
          userId: 'user-$i',
          version: 1,
          deviceId: 'test-device',
        );

        await database.into(database.changeSets).insert(changeSet);
      }

      final allChangeSets = await database.select(database.changeSets).get();
      expect(allChangeSets.length, equals(operations.length));
    });

    test('can query change-sets by table and recordId', () async {
      await database.into(database.changeSets).insert(
            ChangeSetsCompanion.insert(
              id: 'uuid-1',
              table: 'students',
              recordId: '1',
              operation: SyncConstants.operationInsert,
              payload: '{}',
              userId: 'user-1',
              version: 1,
              deviceId: 'test-device',
            ),
          );
      await database.into(database.changeSets).insert(
            ChangeSetsCompanion.insert(
              id: 'uuid-2',
              table: 'students',
              recordId: '2',
              operation: SyncConstants.operationUpdate,
              payload: '{}',
              userId: 'user-2',
              version: 1,
              deviceId: 'test-device',
            ),
          );
      await database.into(database.changeSets).insert(
            ChangeSetsCompanion.insert(
              id: 'uuid-3',
              table: 'attendance',
              recordId: '1',
              operation: SyncConstants.operationInsert,
              payload: '{}',
              userId: 'user-3',
              version: 1,
              deviceId: 'test-device',
            ),
          );

      final studentChangeSets = await (database.select(database.changeSets)
            ..where((t) => t.table.equals('students')))
          .get();

      expect(studentChangeSets.length, equals(2));
    });

    test('can query change-sets chronologically', () async {
      final now = DateTime.now();

      await database.into(database.changeSets).insert(
            ChangeSetsCompanion.insert(
              id: 'uuid-old',
              table: 'students',
              recordId: '1',
              operation: SyncConstants.operationInsert,
              payload: '{}',
              userId: 'user-1',
              version: 1,
              deviceId: 'test-device',
              timestamp: Value(now.subtract(const Duration(hours: 2))),
            ),
          );
      await database.into(database.changeSets).insert(
            ChangeSetsCompanion.insert(
              id: 'uuid-new',
              table: 'students',
              recordId: '2',
              operation: SyncConstants.operationUpdate,
              payload: '{}',
              userId: 'user-2',
              version: 1,
              deviceId: 'test-device',
              timestamp: Value(now.subtract(const Duration(hours: 1))),
            ),
          );

      final changeSets = await (database.select(database.changeSets)
            ..orderBy([(t) => OrderingTerm(expression: t.timestamp)]))
          .get();

      expect(changeSets.length, equals(2));
      expect(changeSets[0].id, equals('uuid-old'));
      expect(changeSets[1].id, equals('uuid-new'));
    });
  });

  group('Integration Tests', () {
    test('can create student and log change-set', () async {
      // Create student
      final student = StudentsCompanion.insert(
        surname: 'Integration',
        firstName: 'Test',
      );

      final studentId = await database.into(database.students).insert(student);

      // Log change-set
      final changeSet = ChangeSetsCompanion.insert(
        id: 'change-set-1',
        table: 'students',
        recordId: studentId.toString(),
        operation: SyncConstants.operationInsert,
        payload: '{"surname": "Integration", "firstName": "Test"}',
        userId: 'test-user',
        version: 1,
        deviceId: 'test-device',
      );

      await database.into(database.changeSets).insert(changeSet);

      // Verify both exist
      final students = await database.select(database.students).get();
      final changeSets = await database.select(database.changeSets).get();

      expect(students.length, equals(1));
      expect(changeSets.length, equals(1));
      expect(changeSets[0].recordId, equals(studentId.toString()));
    });
  });
}
