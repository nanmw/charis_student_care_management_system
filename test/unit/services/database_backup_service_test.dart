import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/services/database_backup_service.dart';

void main() {
  late AppDatabase db;
  late Directory tempDir;

  setUp(() async {
    db = AppDatabase.test();
    tempDir = Directory.systemTemp.createTempSync('charis_backup_');
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('suggestedFileName uses yyyy-MM-dd', () {
    expect(
      DatabaseBackupService.suggestedFileName(DateTime(2026, 9, 8)),
      'charis_backup_2026-09-08.db',
    );
  });

  test('VACUUM INTO produces a readable copy with known rows', () async {
    await db.into(db.students).insert(
          StudentsCompanion.insert(
            surname: 'Zeelie',
            firstName: 'Kirstin',
          ),
        );

    final dest = File(p.join(tempDir.path, 'charis_backup_test.db'));
    await DatabaseBackupService(db).backupTo(dest.path);

    expect(dest.existsSync(), isTrue);
    expect(dest.lengthSync(), greaterThan(0));

    final copy = AppDatabase.fromFile(dest);
    try {
      final students = await copy.select(copy.students).get();
      expect(students, hasLength(1));
      expect(students.single.surname, 'Zeelie');
      expect(students.single.firstName, 'Kirstin');
    } finally {
      await copy.close();
    }
  });

  test('backupTo replaces an existing destination file', () async {
    await db.into(db.students).insert(
          StudentsCompanion.insert(surname: 'Mpushe', firstName: 'Thembelani'),
        );

    final dest = File(p.join(tempDir.path, 'existing.db'));
    await dest.writeAsString('stale');

    await DatabaseBackupService(db).backupTo(dest.path);

    final copy = AppDatabase.fromFile(dest);
    try {
      final students = await copy.select(copy.students).get();
      expect(students.single.surname, 'Mpushe');
    } finally {
      await copy.close();
    }
  });
}
