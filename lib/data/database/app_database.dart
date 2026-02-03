import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'tables/students.dart';
import 'tables/change_sets.dart';
import 'tables/attendance.dart';
import 'tables/tests.dart';
import 'tables/payments.dart';

part 'app_database.g.dart';

/// Main database class (plain SQLite; encryption can be re-added later with platform-specific setup)
@DriftDatabase(tables: [Students, ChangeSets, Attendance, Tests, Payments])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Creates a test database instance using in-memory database
  /// Useful for unit testing without file system dependencies
  AppDatabase.test() : super(_openTestConnection());

  @override
  int get schemaVersion => 10;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // Create indexes for efficient queries
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_students_surname ON students(surname)',);
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_students_status ON students(status)',);
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_changesets_table_record ON change_sets("table", record_id)',);
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_changesets_timestamp ON change_sets(timestamp)',);
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_changesets_user_id ON change_sets(user_id)',);
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // #region agent log
        try {
          final logFile = File(r'c:\Users\Mi\projects\desktop_apps\flutter_desktop\charis_student_care_management_system\.cursor\debug.log');
          final entry = jsonEncode({
            'id': 'log_${DateTime.now().millisecondsSinceEpoch}',
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'location': 'app_database.dart:onUpgrade',
            'message': 'Migration started',
            'data': {'from': from, 'to': to, 'schemaVersion': 10},
            'sessionId': 'debug-session',
            'runId': 'run1',
            'hypothesisId': 'A',
          });
          logFile.writeAsStringSync('$entry\n', mode: FileMode.append);
        } catch (e) {}
        // #endregion
        if (from < 2) {
          await customStatement('ALTER TABLE students ADD COLUMN year TEXT');
          await customStatement('ALTER TABLE students ADD COLUMN mode TEXT');
          await customStatement('ALTER TABLE students ADD COLUMN contact_info TEXT');
          await customStatement('ALTER TABLE students ADD COLUMN email TEXT');
        }
        if (from < 3) {
          // Remove Correspondence: migrate status and mode to valid values
          await customStatement(
              "UPDATE students SET status = 'Transferred' WHERE status = 'Correspondence'");
          await customStatement(
              "UPDATE students SET mode = 'Hybrid' WHERE mode = 'Part-time' OR mode = 'Correspondence'");
        }
        if (from < 5) {
          await customStatement('ALTER TABLE students ADD COLUMN admission_year TEXT');
        }
        if (from < 6) {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS tests (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              student_id INTEGER NOT NULL,
              score INTEGER NOT NULL,
              label TEXT,
              created_at INTEGER NOT NULL,
              CHECK(score >= 0 AND score <= 100)
            )
          ''');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_tests_student_id ON tests(student_id)');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_tests_student_created ON tests(student_id, created_at)');
        }
        if (from < 7) {
          // Populate admissionYear based on year level
          await customStatement(
              "UPDATE students SET admission_year = '2026' WHERE year = 'Year 1' AND admission_year IS NULL");
          await customStatement(
              "UPDATE students SET admission_year = '2025' WHERE year = 'Year 2' AND admission_year IS NULL");
          await customStatement(
              "UPDATE students SET admission_year = '2024' WHERE year = 'Year 3' AND admission_year IS NULL");
        }
        if (from < 8) {
          await customStatement('ALTER TABLE students ADD COLUMN handbook INTEGER DEFAULT 0');
          await customStatement('ALTER TABLE students ADD COLUMN media_release INTEGER DEFAULT 0');
          await customStatement('ALTER TABLE students ADD COLUMN accident_waiver INTEGER DEFAULT 0');
        }
        if (from < 4) {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS attendance (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              date INTEGER NOT NULL,
              student_id INTEGER NOT NULL,
              present INTEGER NOT NULL DEFAULT 0,
              notes TEXT,
              UNIQUE(date, student_id),
              CHECK(present IN (0, 1))
            )
          ''');
          await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_date_student ON attendance(date, student_id)');
        }
        if (from < 9) {
          // #region agent log
          try {
            final logFile = File(r'c:\Users\Mi\projects\desktop_apps\flutter_desktop\charis_student_care_management_system\.cursor\debug.log');
            final entry = jsonEncode({
              'id': 'log_${DateTime.now().millisecondsSinceEpoch}',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'location': 'app_database.dart:onUpgrade',
              'message': 'Running migration from < 9',
              'data': {'from': from},
              'sessionId': 'debug-session',
              'runId': 'run1',
              'hypothesisId': 'A',
            });
            logFile.writeAsStringSync('$entry\n', mode: FileMode.append);
          } catch (e) {}
          // #endregion
          // Remove handbook, media_release, and accident_waiver columns from attendance table
          // SQLite doesn't support DROP COLUMN, so we recreate the table
          await customStatement('''
            CREATE TABLE attendance_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              date INTEGER NOT NULL,
              student_id INTEGER NOT NULL,
              present INTEGER NOT NULL DEFAULT 0,
              notes TEXT,
              UNIQUE(date, student_id),
              CHECK(present IN (0, 1))
            )
          ''');
          await customStatement('''
            INSERT INTO attendance_new (id, date, student_id, present, notes)
            SELECT id, date, student_id, present, notes FROM attendance
          ''');
          await customStatement('DROP TABLE attendance');
          await customStatement('ALTER TABLE attendance_new RENAME TO attendance');
          await customStatement(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_date_student ON attendance(date, student_id)');
          // #region agent log
          try {
            final logFile = File(r'c:\Users\Mi\projects\desktop_apps\flutter_desktop\charis_student_care_management_system\.cursor\debug.log');
            final entry = jsonEncode({
              'id': 'log_${DateTime.now().millisecondsSinceEpoch}',
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'location': 'app_database.dart:onUpgrade',
              'message': 'Migration from < 9 completed',
              'data': {'from': from},
              'sessionId': 'debug-session',
              'runId': 'run1',
              'hypothesisId': 'A',
            });
            logFile.writeAsStringSync('$entry\n', mode: FileMode.append);
          } catch (e) {}
          // #endregion
        }
        if (from < 10) {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS payments (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              student_id INTEGER NOT NULL,
              year TEXT NOT NULL,
              jan REAL NOT NULL DEFAULT 0,
              feb REAL NOT NULL DEFAULT 0,
              mar REAL NOT NULL DEFAULT 0,
              apr REAL NOT NULL DEFAULT 0,
              may REAL NOT NULL DEFAULT 0,
              jun REAL NOT NULL DEFAULT 0,
              jul REAL NOT NULL DEFAULT 0,
              aug REAL NOT NULL DEFAULT 0,
              sep REAL NOT NULL DEFAULT 0,
              oct REAL NOT NULL DEFAULT 0,
              nov REAL NOT NULL DEFAULT 0,
              dec REAL NOT NULL DEFAULT 0,
              lump_sum REAL NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              UNIQUE(student_id, year)
            )
          ''');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_payments_student_year ON payments(student_id, year)');
        }
      },
    );
  }
}

/// Opens a database connection (plain SQLite; no encryption on disk)
LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'charis_student_care.db'));

    return NativeDatabase.createInBackground(
      file,
      setup: (database) {
        database.execute('PRAGMA foreign_keys = ON');
      },
    );
  });
}

/// Opens a test database connection (in-memory, no encryption)
/// Used for unit testing
LazyDatabase _openTestConnection() {
  return LazyDatabase(() async {
    return NativeDatabase.memory();
  });
}
