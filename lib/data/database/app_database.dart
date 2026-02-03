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
import 'tables/subjects.dart';

part 'app_database.g.dart';

/// Main database class (plain SQLite; encryption can be re-added later with platform-specific setup)
@DriftDatabase(tables: [Students, ChangeSets, Attendance, Tests, Payments, Subjects])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Creates a test database instance using in-memory database
  /// Useful for unit testing without file system dependencies
  AppDatabase.test() : super(_openTestConnection());

  @override
  int get schemaVersion => 12;

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
        await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_subjects_year ON subjects(year)');
        
        // Seed first-year subjects
        final firstYearSubjects = [
          'A Sure Foundation',
          'Healing',
          'Life Foundations',
          'Basics of Righteousness',
          'Possess The Land',
          'Prosperity God\'s Way',
          'Holy Spirit I',
          'Discipleship Evangelism I',
          'The Heart of The Gospel',
          'Principles of Grace & Faith',
          'Holy Spirit II',
          'Discipleship Evangelism II',
          'Fruit of The Spirit',
          'Marriage & Family',
          'Romans',
          'Holy Spirit III',
          'Relationship with God I',
          'Old Testament Survey 1',
          'Discipleship Evangelism III',
          'New Covenant Prayer',
          'Galatians',
          'Introduction To The Bible',
          'Relationship With God II',
          'Basic Bible Doctrines',
          'Establishing A Prosperous Soul',
          'Old Testament Survey II',
          'The Fundamentals Of Faith',
          'Prayer Minister Training',
          'Finally, My Brethren',
          'Biblical Ethics and Morals',
          'Receiving From God I',
          'Old Testament Survey III',
          'The Ministry Of Jesus I',
          'Let Freedom Reign',
          'Love Of God',
          'Old Testament Survey IV',
          'The Ministry Of Jesus II',
          'Old Testament Survey V',
          'Operating In God\'s Best',
          'Foundations Of Evangelism',
          'Receiving From God II',
          'Old Testament Survey VI',
          'Rehearsal',
          'Graduation',
        ];
        
        for (final subjectName in firstYearSubjects) {
          final escapedName = subjectName.replaceAll("'", "''");
          await customStatement('''
            INSERT OR IGNORE INTO subjects (name, year) VALUES ('$escapedName', 'Year 1')
          ''');
        }
        
        // Seed second-year subjects
        final secondYearSubjects = [
          'How To Get Along With People',
          'Laws of The Kingdom',
          'How To Study The Bible',
          'Biblical Leadership',
          'Healing II',
          'New Testament Survey I',
          'Living in Balance',
          'IAG Practical Ministry',
          'Practical Skills for Godly Relationships',
          '20/20 Vision',
          'Bible Covenants',
          'How to Flow in The Gifts',
          'Public Speaking',
          'Lifestyle of Intimacy',
          'Principles of Godly Leadership',
          'Answers to Important Questions I',
          'The Church Defined',
          'Biblical Basis for Missions',
          'Introduction to Money Mastery',
          'Imparting Success to The Next Gen',
          'Life of Christ',
          'Walking In The Spirit',
          'Making of A Minister I',
          'Excellence In Ministry',
          'IAG Sacerdotal Duties',
          'Goal of The Cross',
          'Answers to Important Question II',
          'New Testament Survey II',
          'Advanced Bible Doctrines',
          'Making of A Minister II',
          'Wisdom & Maturity',
          'Church History',
          'In Christ Realities',
          'Acts: Power for Supernatural Living',
          'Foundational Truths for Godly Ministry',
          'Heart Matters',
          'Biblical Worldview',
          'Who is Man',
          'Weddings',
          'Funerals',
          'Rehearsal',
          'Graduation',
        ];
        
        for (final subjectName in secondYearSubjects) {
          final escapedName = subjectName.replaceAll("'", "''");
          await customStatement('''
            INSERT OR IGNORE INTO subjects (name, year) VALUES ('$escapedName', 'Year 2')
          ''');
        }
        
        // Seed third-year subjects
        final thirdYearSubjects = [
          'Vision Development Intro',
          'Advice From an Older Minister',
          'Organizational Mastery',
          'Time Management',
          'Sound Doctrine',
          'Business Model Generation Canvas',
          'How to Teach & Preach Effectively',
          'How to Teach',
          'Boundaries',
          'The Evolution of Ministry',
          'Developing Healthy Relationships',
          'Change Mastery',
          'Team Building',
          'Making Cents',
          'Business As Missions',
          'Business Planning',
          'Anatomy of Revival',
          'Strategic Planning',
          'Divine Guidance',
          'Leadership 101',
          'Money Mastery',
          'Missions',
          'Creatively Communicating The Gospel',
          'Basic CEO 1',
          'Effective Counseling',
          'Conflict Resolution',
          'Leadership',
          'Building a Successful Business',
          'Purpose of Marriage, Spiritual Formation',
          'How to Disciple',
          'Rehearsal',
          'Graduation',
        ];
        
        for (final subjectName in thirdYearSubjects) {
          final escapedName = subjectName.replaceAll("'", "''");
          await customStatement('''
            INSERT OR IGNORE INTO subjects (name, year) VALUES ('$escapedName', 'Year 3')
          ''');
        }
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
        if (from < 11) {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS subjects (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              name TEXT NOT NULL,
              year TEXT NOT NULL,
              UNIQUE(name, year)
            )
          ''');
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_subjects_year ON subjects(year)');
          
          // Seed first-year subjects
          final firstYearSubjects = [
            'A Sure Foundation',
            'Healing',
            'Life Foundations',
            'Basics of Righteousness',
            'Possess The Land',
            'Prosperity God\'s Way',
            'Holy Spirit I',
            'Discipleship Evangelism I',
            'The Heart of The Gospel',
            'Principles of Grace & Faith',
            'Holy Spirit II',
            'Discipleship Evangelism II',
            'Fruit of The Spirit',
            'Marriage & Family',
            'Romans',
            'Holy Spirit III',
            'Relationship with God I',
            'Old Testament Survey 1',
            'Discipleship Evangelism III',
            'New Covenant Prayer',
            'Galatians',
            'Introduction To The Bible',
            'Relationship With God II',
            'Basic Bible Doctrines',
            'Establishing A Prosperous Soul',
            'Old Testament Survey II',
            'The Fundamentals Of Faith',
            'Prayer Minister Training',
            'Finally, My Brethren',
            'Biblical Ethics and Morals',
            'Receiving From God I',
            'Old Testament Survey III',
            'The Ministry Of Jesus I',
            'Let Freedom Reign',
            'Love Of God',
            'Old Testament Survey IV',
            'The Ministry Of Jesus II',
            'Old Testament Survey V',
            'Operating In God\'s Best',
            'Foundations Of Evangelism',
            'Receiving From God II',
            'Old Testament Survey VI',
            'Rehearsal',
            'Graduation',
          ];
          
          // Insert subjects using batch insert for efficiency
          for (final subjectName in firstYearSubjects) {
            // Escape single quotes in subject names for SQL
            final escapedName = subjectName.replaceAll("'", "''");
            await customStatement('''
              INSERT OR IGNORE INTO subjects (name, year) VALUES ('$escapedName', 'Year 1')
            ''');
          }
          
          // Seed second-year subjects
          final secondYearSubjects = [
            'How To Get Along With People',
            'Laws of The Kingdom',
            'How To Study The Bible',
            'Biblical Leadership',
            'Healing II',
            'New Testament Survey I',
            'Living in Balance',
            'IAG Practical Ministry',
            'Practical Skills for Godly Relationships',
            '20/20 Vision',
            'Bible Covenants',
            'How to Flow in The Gifts',
            'Public Speaking',
            'Lifestyle of Intimacy',
            'Principles of Godly Leadership',
            'Answers to Important Questions I',
            'The Church Defined',
            'Biblical Basis for Missions',
            'Introduction to Money Mastery',
            'Imparting Success to The Next Gen',
            'Life of Christ',
            'Walking In The Spirit',
            'Making of A Minister I',
            'Excellence In Ministry',
            'IAG Sacerdotal Duties',
            'Goal of The Cross',
            'Answers to Important Question II',
            'New Testament Survey II',
            'Advanced Bible Doctrines',
            'Making of A Minister II',
            'Wisdom & Maturity',
            'Church History',
            'In Christ Realities',
            'Acts: Power for Supernatural Living',
            'Foundational Truths for Godly Ministry',
            'Heart Matters',
            'Biblical Worldview',
            'Who is Man',
            'Weddings',
            'Funerals',
            'Rehearsal',
            'Graduation',
          ];
          
          // Insert Year 2 subjects
          for (final subjectName in secondYearSubjects) {
            // Escape single quotes in subject names for SQL
            final escapedName = subjectName.replaceAll("'", "''");
            await customStatement('''
              INSERT OR IGNORE INTO subjects (name, year) VALUES ('$escapedName', 'Year 2')
            ''');
          }
          
          // Seed third-year subjects
          final thirdYearSubjects = [
            'Vision Development Intro',
            'Advice From an Older Minister',
            'Organizational Mastery',
            'Time Management',
            'Sound Doctrine',
            'Business Model Generation Canvas',
            'How to Teach & Preach Effectively',
            'How to Teach',
            'Boundaries',
            'The Evolution of Ministry',
            'Developing Healthy Relationships',
            'Change Mastery',
            'Team Building',
            'Making Cents',
            'Business As Missions',
            'Business Planning',
            'Anatomy of Revival',
            'Strategic Planning',
            'Divine Guidance',
            'Leadership 101',
            'Money Mastery',
            'Missions',
            'Creatively Communicating The Gospel',
            'Basic CEO 1',
            'Effective Counseling',
            'Conflict Resolution',
            'Leadership',
            'Building a Successful Business',
            'Purpose of Marriage, Spiritual Formation',
            'How to Disciple',
            'Rehearsal',
            'Graduation',
          ];
          
          // Insert Year 3 subjects
          for (final subjectName in thirdYearSubjects) {
            // Escape single quotes in subject names for SQL
            final escapedName = subjectName.replaceAll("'", "''");
            await customStatement('''
              INSERT OR IGNORE INTO subjects (name, year) VALUES ('$escapedName', 'Year 3')
            ''');
          }
        }
        if (from < 12) {
          // Seed second-year subjects for databases already at version 11
          final secondYearSubjects = [
            'How To Get Along With People',
            'Laws of The Kingdom',
            'How To Study The Bible',
            'Biblical Leadership',
            'Healing II',
            'New Testament Survey I',
            'Living in Balance',
            'IAG Practical Ministry',
            'Practical Skills for Godly Relationships',
            '20/20 Vision',
            'Bible Covenants',
            'How to Flow in The Gifts',
            'Public Speaking',
            'Lifestyle of Intimacy',
            'Principles of Godly Leadership',
            'Answers to Important Questions I',
            'The Church Defined',
            'Biblical Basis for Missions',
            'Introduction to Money Mastery',
            'Imparting Success to The Next Gen',
            'Life of Christ',
            'Walking In The Spirit',
            'Making of A Minister I',
            'Excellence In Ministry',
            'IAG Sacerdotal Duties',
            'Goal of The Cross',
            'Answers to Important Question II',
            'New Testament Survey II',
            'Advanced Bible Doctrines',
            'Making of A Minister II',
            'Wisdom & Maturity',
            'Church History',
            'In Christ Realities',
            'Acts: Power for Supernatural Living',
            'Foundational Truths for Godly Ministry',
            'Heart Matters',
            'Biblical Worldview',
            'Who is Man',
            'Weddings',
            'Funerals',
            'Rehearsal',
            'Graduation',
          ];
          
          // Insert Year 2 subjects
          for (final subjectName in secondYearSubjects) {
            final escapedName = subjectName.replaceAll("'", "''");
            await customStatement('''
              INSERT OR IGNORE INTO subjects (name, year) VALUES ('$escapedName', 'Year 2')
            ''');
          }
          
          // Seed third-year subjects
          final thirdYearSubjects = [
            'Vision Development Intro',
            'Advice From an Older Minister',
            'Organizational Mastery',
            'Time Management',
            'Sound Doctrine',
            'Business Model Generation Canvas',
            'How to Teach & Preach Effectively',
            'How to Teach',
            'Boundaries',
            'The Evolution of Ministry',
            'Developing Healthy Relationships',
            'Change Mastery',
            'Team Building',
            'Making Cents',
            'Business As Missions',
            'Business Planning',
            'Anatomy of Revival',
            'Strategic Planning',
            'Divine Guidance',
            'Leadership 101',
            'Money Mastery',
            'Missions',
            'Creatively Communicating The Gospel',
            'Basic CEO 1',
            'Effective Counseling',
            'Conflict Resolution',
            'Leadership',
            'Building a Successful Business',
            'Purpose of Marriage, Spiritual Formation',
            'How to Disciple',
            'Rehearsal',
            'Graduation',
          ];
          
          // Insert Year 3 subjects
          for (final subjectName in thirdYearSubjects) {
            final escapedName = subjectName.replaceAll("'", "''");
            await customStatement('''
              INSERT OR IGNORE INTO subjects (name, year) VALUES ('$escapedName', 'Year 3')
            ''');
          }
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
