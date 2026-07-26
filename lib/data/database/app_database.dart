import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'tables/academic_sessions.dart';
import 'tables/classes.dart';
import 'tables/students.dart';
import 'tables/change_sets.dart';
import 'tables/attendance.dart';
import 'tables/tests.dart';
import 'tables/payments.dart';
import 'tables/subjects.dart';
import 'subject_curriculum_order.dart';
import 'tables/app_settings.dart';
import 'tables/ministry_entries.dart';
import 'tables/mission_payment_schedule.dart';
import 'tables/mission_participations.dart';
import 'tables/mission_payments.dart';
import 'tables/mission_locations.dart';
import 'tables/missions.dart';
import 'tables/users.dart';
import 'tables/sync_record_mapping.dart';
import 'tables/sync_conflicts.dart';

part 'app_database.g.dart';

/// Main database class (plain SQLite; encryption can be re-added later with platform-specific setup)
@DriftDatabase(
  tables: [
    AcademicSessions,
    Classes,
    Students,
    ChangeSets,
    Attendance,
    Tests,
    Payments,
    Subjects,
    AppSettings,
    MinistryEntries,
    MissionPaymentSchedule,
    MissionLocations,
    Missions,
    MissionParticipations,
    MissionPayments,
    Users,
    SyncRecordMapping,
    SyncConflicts,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  /// Opens the database from a specific file (e.g. for scripts or backup).
  AppDatabase.fromFile(File file) : super(_openFileConnection(file));

  /// Creates a test database instance using in-memory database
  /// Useful for unit testing without file system dependencies
  AppDatabase.test() : super(_openTestConnection());

  @override
  int get schemaVersion => 35;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
        // Create indexes for efficient queries
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_students_surname ON students(surname)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_students_status ON students(status)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_changesets_table_record ON change_sets("table", record_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_changesets_timestamp ON change_sets(timestamp)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_changesets_user_id ON change_sets(user_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_classes_name ON classes(name)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_classes_facilitator_user_id ON classes(facilitator_user_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_students_class_id ON students(class_id)',
        );
        await customStatement(
          'CREATE INDEX IF NOT EXISTS idx_subjects_class_id ON subjects(class_id)',
        );

        // Seed classes (Year 1, Year 2, Year 3)
        await customStatement(
          "INSERT OR IGNORE INTO classes (name, sort_order) VALUES ('Year 1', 1), ('Year 2', 2), ('Year 3', 3)",
        );

        // Seed first/second/third-year subjects with curriculum sort_order
        for (final entry in SubjectCurriculumOrder.byClassId.entries) {
          final classId = entry.key;
          final names = entry.value;
          for (var i = 0; i < names.length; i++) {
            final escapedName = names[i].replaceAll("'", "''");
            await customStatement('''
              INSERT OR IGNORE INTO subjects (name, class_id, sort_order)
              VALUES ('$escapedName', $classId, $i)
            ''');
          }
        }

        // Seed academic sessions (current and previous) if none exist yet.
        await _ensureInitialAcademicSessions();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        // #region agent log
        try {
          final logFile = File(
            r'c:\Users\Mi\projects\desktop_apps\flutter_desktop\charis_student_care_management_system\.cursor\debug.log',
          );
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
        } catch (e) {
          // Debug migration logging only; ignore failures.
        }
        // #endregion
        if (from < 2) {
          await customStatement('ALTER TABLE students ADD COLUMN year TEXT');
          await customStatement('ALTER TABLE students ADD COLUMN mode TEXT');
          await customStatement(
            'ALTER TABLE students ADD COLUMN contact_info TEXT',
          );
          await customStatement('ALTER TABLE students ADD COLUMN email TEXT');
        }
        if (from < 3) {
          // Remove Correspondence: migrate status and mode to valid values
          await customStatement(
            "UPDATE students SET status = 'Transferred' WHERE status = 'Correspondence'",
          );
          await customStatement(
            "UPDATE students SET mode = 'Hybrid' WHERE mode = 'Part-time' OR mode = 'Correspondence'",
          );
        }
        if (from < 5) {
          await customStatement(
            'ALTER TABLE students ADD COLUMN admission_year TEXT',
          );
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
            'CREATE INDEX IF NOT EXISTS idx_tests_student_id ON tests(student_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_tests_student_created ON tests(student_id, created_at)',
          );
        }
        if (from < 7) {
          // Populate admissionYear based on year level
          await customStatement(
            "UPDATE students SET admission_year = '2026' WHERE year = 'Year 1' AND admission_year IS NULL",
          );
          await customStatement(
            "UPDATE students SET admission_year = '2025' WHERE year = 'Year 2' AND admission_year IS NULL",
          );
          await customStatement(
            "UPDATE students SET admission_year = '2024' WHERE year = 'Year 3' AND admission_year IS NULL",
          );
        }
        if (from < 8) {
          await customStatement(
            'ALTER TABLE students ADD COLUMN handbook INTEGER DEFAULT 0',
          );
          await customStatement(
            'ALTER TABLE students ADD COLUMN media_release INTEGER DEFAULT 0',
          );
          await customStatement(
            'ALTER TABLE students ADD COLUMN accident_waiver INTEGER DEFAULT 0',
          );
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
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_date_student ON attendance(date, student_id)',
          );
        }
        if (from < 9) {
          // #region agent log
          try {
            final logFile = File(
              r'c:\Users\Mi\projects\desktop_apps\flutter_desktop\charis_student_care_management_system\.cursor\debug.log',
            );
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
          } catch (e) {
            // Debug migration logging only; ignore failures.
          }
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
          await customStatement(
            'ALTER TABLE attendance_new RENAME TO attendance',
          );
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_date_student ON attendance(date, student_id)',
          );
          // #region agent log
          try {
            final logFile = File(
              r'c:\Users\Mi\projects\desktop_apps\flutter_desktop\charis_student_care_management_system\.cursor\debug.log',
            );
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
          } catch (e) {
            // Debug migration logging only; ignore failures.
          }
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
            'CREATE INDEX IF NOT EXISTS idx_payments_student_year ON payments(student_id, year)',
          );
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
            'CREATE INDEX IF NOT EXISTS idx_subjects_year ON subjects(year)',
          );

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
        if (from < 13) {
          // Update change_sets table to support DELETE operation
          // SQLite doesn't support modifying CHECK constraints directly, so we recreate the table
          await customStatement('''
            CREATE TABLE change_sets_new (
              id TEXT NOT NULL PRIMARY KEY,
              "table" TEXT NOT NULL,
              record_id TEXT NOT NULL,
              operation TEXT NOT NULL CHECK(operation IN ('INSERT', 'UPDATE', 'STATUS_CHANGE', 'DELETE')),
              payload TEXT NOT NULL,
              timestamp INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
              user_id TEXT NOT NULL,
              version INTEGER NOT NULL
            )
          ''');
          await customStatement('''
            INSERT INTO change_sets_new (id, "table", record_id, operation, payload, timestamp, user_id, version)
            SELECT id, "table", record_id, operation, payload, timestamp, user_id, version FROM change_sets
          ''');
          await customStatement('DROP TABLE change_sets');
          await customStatement(
            'ALTER TABLE change_sets_new RENAME TO change_sets',
          );
          // Recreate indexes
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_changesets_table_record ON change_sets("table", record_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_changesets_timestamp ON change_sets(timestamp)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_changesets_user_id ON change_sets(user_id)',
          );
        }
        if (from < 14) {
          await customStatement(
              'ALTER TABLE tests ADD COLUMN subject_id INTEGER',);
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_tests_subject_id ON tests(subject_id)',);
        }
        if (from < 15) {
          await customStatement(
              'ALTER TABLE tests ADD COLUMN updated_at INTEGER',);
          await customStatement(
              'CREATE INDEX IF NOT EXISTS idx_tests_updated_at ON tests(updated_at)',);
        }
        if (from < 16) {
          await customStatement(
              'ALTER TABLE tests ADD COLUMN academic_session TEXT',);
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_tests_academic_session ON tests(academic_session)',
          );
        }
        if (from < 17) {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS app_settings (
              key TEXT PRIMARY KEY NOT NULL,
              value TEXT
            )
          ''');
        }
        if (from < 18) {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS ministry_entries (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              student_id INTEGER NOT NULL,
              year TEXT NOT NULL,
              ministry_type TEXT NOT NULL,
              date INTEGER NOT NULL,
              hours REAL NOT NULL,
              supervisor TEXT,
              approved INTEGER NOT NULL DEFAULT 0,
              notes TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER
            )
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_ministry_entries_student_id ON ministry_entries(student_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_ministry_entries_date ON ministry_entries(date)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_ministry_entries_approved ON ministry_entries(approved)',
          );
        }
        if (from < 20) {
          // Ministry entries: add term and context for spreadsheet-style summary (Year/Mode tabs, Term 1/2/3).
          // term: default 1 for existing rows; academic_year/study_mode backfilled from students.
          await customStatement(
            'ALTER TABLE ministry_entries ADD COLUMN term INTEGER NOT NULL DEFAULT 1',
          );
          await customStatement(
            'ALTER TABLE ministry_entries ADD COLUMN academic_year TEXT',
          );
          await customStatement(
            'ALTER TABLE ministry_entries ADD COLUMN study_mode TEXT',
          );
          await customStatement('''
            UPDATE ministry_entries SET
              academic_year = (SELECT year FROM students WHERE students.id = ministry_entries.student_id),
              study_mode = (SELECT mode FROM students WHERE students.id = ministry_entries.student_id)
            WHERE academic_year IS NULL
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_ministry_entries_student_academic_mode_term ON ministry_entries(student_id, academic_year, study_mode, term)',
          );
        }
        if (from < 22) {
          await customStatement('DROP TABLE IF EXISTS mission_payments');
          await customStatement('DROP TABLE IF EXISTS mission_participations');
          await customStatement('DROP TABLE IF EXISTS missions');
        }
        if (from < 23) {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS mission_payment_schedule (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              student_id INTEGER NOT NULL,
              year TEXT NOT NULL,
              trip_selected TEXT,
              date INTEGER,
              amount REAL NOT NULL DEFAULT 0,
              mar REAL NOT NULL DEFAULT 0,
              apr REAL NOT NULL DEFAULT 0,
              may REAL NOT NULL DEFAULT 0,
              jun REAL NOT NULL DEFAULT 0,
              jul REAL NOT NULL DEFAULT 0,
              aug REAL NOT NULL DEFAULT 0,
              sep REAL NOT NULL DEFAULT 0,
              oct REAL NOT NULL DEFAULT 0,
              comment TEXT,
              UNIQUE(student_id, year)
            )
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_mission_payment_schedule_student_year ON mission_payment_schedule(student_id, year)',
          );
        }
        if (from < 24) {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS users (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              username TEXT NOT NULL,
              password_hash TEXT NOT NULL,
              display_name TEXT,
              role TEXT NOT NULL,
              is_active INTEGER NOT NULL DEFAULT 1,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL
            )
          ''');
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users(username)',
          );
        }
        if (from < 25) {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS missions (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              title TEXT NOT NULL,
              location TEXT NOT NULL,
              start_date INTEGER NOT NULL,
              end_date INTEGER NOT NULL,
              slots_total INTEGER NOT NULL,
              description TEXT,
              is_active INTEGER NOT NULL DEFAULT 1,
              year TEXT NOT NULL,
              amount REAL,
              mode TEXT NOT NULL,
              created_at INTEGER NOT NULL DEFAULT (unixepoch('subsec')),
              updated_at INTEGER
            )
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_missions_year ON missions(year)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_missions_start_date ON missions(start_date)',
          );
          await customStatement('''
            CREATE TABLE IF NOT EXISTS mission_participations (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              mission_id INTEGER NOT NULL,
              student_id INTEGER NOT NULL,
              role TEXT NOT NULL,
              amount REAL NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL DEFAULT (unixepoch('subsec')),
              UNIQUE(mission_id, student_id)
            )
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_mission_participations_mission_id ON mission_participations(mission_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_mission_participations_student_id ON mission_participations(student_id)',
          );
          await customStatement('''
            CREATE TABLE IF NOT EXISTS mission_payments (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              mission_participation_id INTEGER NOT NULL,
              payment_date INTEGER NOT NULL,
              amount REAL NOT NULL,
              created_at INTEGER NOT NULL DEFAULT (unixepoch('subsec'))
            )
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_mission_payments_participation ON mission_payments(mission_participation_id)',
          );
        }
        if (from < 26) {
          await customStatement(
            "ALTER TABLE change_sets ADD COLUMN device_id TEXT NOT NULL DEFAULT 'legacy'",
          );
        }
        if (from < 27) {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS mission_locations (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              name TEXT NOT NULL UNIQUE,
              description TEXT,
              is_active INTEGER NOT NULL DEFAULT 1
            )
          ''');
          await customStatement(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_mission_locations_name ON mission_locations(name)',
          );
        }
        if (from < 28) {
          const seedLocations = [
            'Walsall',
            'Knysna',
            'Port Elizabeth',
            'Bloemfontein',
            'Durban',
            'Johannesburg I',
            'Lesotho',
            'Cape Town I',
            'Uganda',
            'Heidelberg I',
            'Kenya',
            'Cape Town II',
            'Nigeria',
            'Johannesburg II',
            'Zimbabwe',
            'Botswana',
            'Heidelberg II',
            'Vietnam',
          ];
          for (final name in seedLocations) {
            final escaped = name.replaceAll("'", "''");
            await customStatement(
              "INSERT OR IGNORE INTO mission_locations (name, is_active) VALUES ('$escaped', 1)",
            );
          }
        }
        if (from < 29) {
          await customStatement('''
            CREATE TABLE IF NOT EXISTS sync_record_mapping (
              table_name TEXT NOT NULL,
              record_id TEXT NOT NULL,
              local_id INTEGER NOT NULL,
              PRIMARY KEY (table_name, record_id)
            )
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sync_record_mapping_table ON sync_record_mapping(table_name)',
          );
          await customStatement('''
            CREATE TABLE IF NOT EXISTS sync_conflicts (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              change_set_id TEXT NOT NULL,
              table_name TEXT NOT NULL,
              record_id TEXT NOT NULL,
              incoming_payload TEXT NOT NULL,
              local_snapshot TEXT NOT NULL,
              detected_at INTEGER NOT NULL,
              source_device_id TEXT NOT NULL
            )
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_sync_conflicts_table ON sync_conflicts(table_name)',
          );
        }
        if (from < 30) {
          // Classes table and migrate students/subjects/ministry_entries to class_id
          await customStatement('''
            CREATE TABLE IF NOT EXISTS classes (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              name TEXT NOT NULL UNIQUE,
              sort_order INTEGER NOT NULL DEFAULT 0,
              facilitator_user_id INTEGER REFERENCES users(id),
              created_at INTEGER NOT NULL DEFAULT (unixepoch('subsec')),
              updated_at INTEGER
            )
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_classes_name ON classes(name)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_classes_facilitator_user_id ON classes(facilitator_user_id)',
          );
          await customStatement(
            "INSERT OR IGNORE INTO classes (name, sort_order) VALUES ('Year 1', 1), ('Year 2', 2), ('Year 3', 3)",
          );

          // Students: add class_id, backfill, recreate without year
          await customStatement(
            'ALTER TABLE students ADD COLUMN class_id INTEGER REFERENCES classes(id)',
          );
          await customStatement('''
            UPDATE students SET class_id = (SELECT id FROM classes WHERE name = students.year) WHERE year IS NOT NULL
          ''');
          await customStatement('''
            CREATE TABLE students_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              surname TEXT NOT NULL,
              first_name TEXT NOT NULL,
              status TEXT NOT NULL DEFAULT 'Active',
              class_id INTEGER REFERENCES classes(id),
              mode TEXT,
              admission_year TEXT,
              contact_info TEXT,
              email TEXT,
              handbook INTEGER NOT NULL DEFAULT 0,
              media_release INTEGER NOT NULL DEFAULT 0,
              accident_waiver INTEGER NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              version INTEGER NOT NULL DEFAULT 1,
              CHECK(status IN ('Active', 'Withdrawn', 'Transferred', 'Correspondence'))
            )
          ''');
          await customStatement('''
            INSERT INTO students_new (id, surname, first_name, status, class_id, mode, admission_year, contact_info, email, handbook, media_release, accident_waiver, created_at, updated_at, version)
            SELECT id, surname, first_name, status, class_id, mode, admission_year, contact_info, email, handbook, media_release, accident_waiver, created_at, updated_at, version FROM students
          ''');
          await customStatement('DROP TABLE students');
          await customStatement('ALTER TABLE students_new RENAME TO students');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_students_surname ON students(surname)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_students_status ON students(status)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_students_class_id ON students(class_id)',
          );

          // Subjects: add class_id, backfill, recreate without year
          await customStatement(
            'ALTER TABLE subjects ADD COLUMN class_id INTEGER REFERENCES classes(id)',
          );
          await customStatement('''
            UPDATE subjects SET class_id = (SELECT id FROM classes WHERE name = subjects.year)
          ''');
          await customStatement('''
            CREATE TABLE subjects_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              name TEXT NOT NULL,
              class_id INTEGER NOT NULL REFERENCES classes(id),
              UNIQUE(name, class_id)
            )
          ''');
          await customStatement('''
            INSERT INTO subjects_new (id, name, class_id) SELECT id, name, class_id FROM subjects
          ''');
          await customStatement('DROP TABLE subjects');
          await customStatement('ALTER TABLE subjects_new RENAME TO subjects');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_subjects_class_id ON subjects(class_id)',
          );

          // Ministry entries: add class_id, backfill, recreate without academic_year (keep year = calendar year)
          await customStatement(
            'ALTER TABLE ministry_entries ADD COLUMN class_id INTEGER REFERENCES classes(id)',
          );
          await customStatement('''
            UPDATE ministry_entries SET class_id = (SELECT id FROM classes WHERE name = ministry_entries.academic_year) WHERE academic_year IS NOT NULL
          ''');
          await customStatement('''
            CREATE TABLE ministry_entries_new (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              student_id INTEGER NOT NULL,
              year TEXT NOT NULL,
              term INTEGER NOT NULL,
              class_id INTEGER REFERENCES classes(id),
              study_mode TEXT,
              ministry_type TEXT NOT NULL,
              date INTEGER NOT NULL,
              hours REAL NOT NULL,
              supervisor TEXT,
              approved INTEGER NOT NULL DEFAULT 0,
              notes TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER
            )
          ''');
          await customStatement('''
            INSERT INTO ministry_entries_new (id, student_id, year, term, class_id, study_mode, ministry_type, date, hours, supervisor, approved, notes, created_at, updated_at)
            SELECT id, student_id, year, term, class_id, study_mode, ministry_type, date, hours, supervisor, approved, notes, created_at, updated_at FROM ministry_entries
          ''');
          await customStatement('DROP TABLE ministry_entries');
          await customStatement(
            'ALTER TABLE ministry_entries_new RENAME TO ministry_entries',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_ministry_entries_student_id ON ministry_entries(student_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_ministry_entries_class_id ON ministry_entries(class_id)',
          );
        }

        if (from < 31) {
          // Create academic_sessions table for existing databases and seed initial sessions.
          await customStatement('''
            CREATE TABLE IF NOT EXISTS academic_sessions (
              id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
              code TEXT NOT NULL UNIQUE,
              start_date INTEGER,
              end_date INTEGER,
              is_active INTEGER NOT NULL DEFAULT 0,
              display_name TEXT
            )
          ''');

          // Add academic_session_id columns to core tables (nullable for legacy data).
          await customStatement(
            'ALTER TABLE tests ADD COLUMN academic_session_id INTEGER REFERENCES academic_sessions(id)',
          );
          await customStatement(
            'ALTER TABLE payments ADD COLUMN academic_session_id INTEGER REFERENCES academic_sessions(id)',
          );
          await customStatement(
            'ALTER TABLE mission_payments ADD COLUMN academic_session_id INTEGER REFERENCES academic_sessions(id)',
          );
          await customStatement(
            'ALTER TABLE mission_payment_schedule ADD COLUMN academic_session_id INTEGER REFERENCES academic_sessions(id)',
          );
          await customStatement(
            'ALTER TABLE attendance ADD COLUMN academic_session_id INTEGER REFERENCES academic_sessions(id)',
          );
          await customStatement(
            'ALTER TABLE students ADD COLUMN academic_session_id INTEGER REFERENCES academic_sessions(id)',
          );
          await customStatement(
            'ALTER TABLE ministry_entries ADD COLUMN academic_session_id INTEGER REFERENCES academic_sessions(id)',
          );
          await customStatement(
            'ALTER TABLE missions ADD COLUMN academic_session_id INTEGER REFERENCES academic_sessions(id)',
          );

          // Backfill academic_sessions from existing string/session data where possible.

          // 1) From tests.academic_session (already stores codes like "2024-2025").
          await customStatement('''
            INSERT OR IGNORE INTO academic_sessions (code)
            SELECT DISTINCT TRIM(academic_session)
            FROM tests
            WHERE academic_session IS NOT NULL AND TRIM(academic_session) <> ''
          ''');
          await customStatement('''
            UPDATE tests
            SET academic_session_id = (
              SELECT id FROM academic_sessions
              WHERE code = TRIM(academic_session)
            )
            WHERE academic_session IS NOT NULL AND TRIM(academic_session) <> ''
              AND academic_session_id IS NULL
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_tests_academic_session_id ON tests(academic_session_id)',
          );

          // 2) From year-based tables: payments, mission_payment_schedule, missions.
          // Map a numeric year Y to session code "Y-(Y+1)".
          await customStatement('''
            INSERT OR IGNORE INTO academic_sessions (code)
            SELECT DISTINCT year || '-' || (CAST(year AS INTEGER) + 1)
            FROM payments
            WHERE year GLOB '[0-9]*'
          ''');
          await customStatement('''
            INSERT OR IGNORE INTO academic_sessions (code)
            SELECT DISTINCT year || '-' || (CAST(year AS INTEGER) + 1)
            FROM mission_payment_schedule
            WHERE year GLOB '[0-9]*'
          ''');
          await customStatement('''
            INSERT OR IGNORE INTO academic_sessions (code)
            SELECT DISTINCT year || '-' || (CAST(year AS INTEGER) + 1)
            FROM missions
            WHERE year GLOB '[0-9]*'
          ''');

          await customStatement('''
            UPDATE payments
            SET academic_session_id = (
              SELECT id FROM academic_sessions
              WHERE code = year || '-' || (CAST(year AS INTEGER) + 1)
            )
            WHERE year GLOB '[0-9]*'
              AND academic_session_id IS NULL
          ''');
          await customStatement('''
            UPDATE mission_payment_schedule
            SET academic_session_id = (
              SELECT id FROM academic_sessions
              WHERE code = year || '-' || (CAST(year AS INTEGER) + 1)
            )
            WHERE year GLOB '[0-9]*'
              AND academic_session_id IS NULL
          ''');
          await customStatement('''
            UPDATE missions
            SET academic_session_id = (
              SELECT id FROM academic_sessions
              WHERE code = year || '-' || (CAST(year AS INTEGER) + 1)
            )
            WHERE year GLOB '[0-9]*'
              AND academic_session_id IS NULL
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_payments_academic_session_id ON payments(academic_session_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_mission_payment_schedule_academic_session_id ON mission_payment_schedule(academic_session_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_missions_academic_session_id ON missions(academic_session_id)',
          );

          // 3) Students and ministry_entries: map from admission_year/year to sessions where possible.
          await customStatement('''
            UPDATE students
            SET academic_session_id = (
              SELECT id FROM academic_sessions
              WHERE code = admission_year || '-' || (CAST(admission_year AS INTEGER) + 1)
            )
            WHERE admission_year GLOB '[0-9]*'
              AND academic_session_id IS NULL
          ''');
          await customStatement('''
            UPDATE ministry_entries
            SET academic_session_id = (
              SELECT id FROM academic_sessions
              WHERE code = year || '-' || (CAST(year AS INTEGER) + 1)
            )
            WHERE year GLOB '[0-9]*'
              AND academic_session_id IS NULL
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_students_academic_session_id ON students(academic_session_id)',
          );
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_ministry_entries_academic_session_id ON ministry_entries(academic_session_id)',
          );

          // 4) Mission payments: derive session from associated mission via mission_participations.
          await customStatement('''
            UPDATE mission_payments
            SET academic_session_id = (
              SELECT mi.academic_session_id
              FROM mission_participations mp
              JOIN missions mi ON mi.id = mp.mission_id
              WHERE mp.id = mission_payments.mission_participation_id
            )
            WHERE academic_session_id IS NULL
          ''');
          await customStatement(
            'CREATE INDEX IF NOT EXISTS idx_mission_payments_academic_session_id ON mission_payments(academic_session_id)',
          );

          // Finally ensure at least current and previous sessions exist and mark one as active.
          await _ensureInitialAcademicSessions();
        }

        if (from < 32) {
          await customStatement(
            'ALTER TABLE users ADD COLUMN allowed_class_id INTEGER REFERENCES classes(id)',
          );
          await customStatement(
            'ALTER TABLE users ADD COLUMN allowed_mode TEXT',
          );
          // Backfill: facilitators who have a class via classes.facilitator_user_id get that class + Full-time.
          await customStatement('''
            UPDATE users
            SET allowed_class_id = (SELECT MIN(id) FROM classes WHERE facilitator_user_id = users.id),
                allowed_mode = 'Full-time'
            WHERE role = 'facilitator'
              AND (SELECT MIN(id) FROM classes WHERE facilitator_user_id = users.id) IS NOT NULL
          ''');
        }

        if (from < 33) {
          // Remap legacy YYYY-YYYY session codes to single-year codes (start year).
          // 1) Ensure single-year session rows exist for every distinct start year.
          await customStatement('''
            INSERT OR IGNORE INTO academic_sessions (code, start_date, end_date, is_active)
            SELECT
              CAST(substr(code, 1, 4) AS TEXT),
              start_date,
              end_date,
              0
            FROM academic_sessions
            WHERE code GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
          ''');
          // Also ensure years referenced by payment year columns exist.
          await customStatement('''
            INSERT OR IGNORE INTO academic_sessions (code)
            SELECT DISTINCT year FROM payments WHERE year GLOB '[0-9]*'
          ''');
          await customStatement('''
            INSERT OR IGNORE INTO academic_sessions (code)
            SELECT DISTINCT year FROM ministry_entries WHERE year GLOB '[0-9]*'
          ''');

          // 2) Re-point FKs from legacy session ids to matching single-year session ids.
          const tables = [
            'payments',
            'tests',
            'attendance',
            'students',
            'ministry_entries',
            'missions',
            'mission_payment_schedule',
            'mission_payments',
          ];
          for (final table in tables) {
            await customStatement('''
              UPDATE $table
              SET academic_session_id = (
                SELECT s2.id
                FROM academic_sessions legacy
                JOIN academic_sessions s2
                  ON s2.code = substr(legacy.code, 1, 4)
                WHERE legacy.id = $table.academic_session_id
                  AND legacy.code GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
              )
              WHERE academic_session_id IS NOT NULL
                AND EXISTS (
                  SELECT 1 FROM academic_sessions legacy
                  WHERE legacy.id = $table.academic_session_id
                    AND legacy.code GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
                )
            ''');
          }

          // 3) Prefer a single-year active session when only a legacy one is active.
          await customStatement('''
            UPDATE academic_sessions
            SET is_active = 1
            WHERE code = (
              SELECT substr(code, 1, 4) FROM academic_sessions
              WHERE is_active = 1
                AND code GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
              LIMIT 1
            )
          ''');
          await customStatement('''
            UPDATE academic_sessions
            SET is_active = 0
            WHERE code GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
          ''');

          await _ensureInitialAcademicSessions();
        }

        if (from < 34) {
          // Rewrite tests.academic_session text from YYYY-YYYY to start year.
          await customStatement('''
            UPDATE tests
            SET academic_session = substr(academic_session, 1, 4)
            WHERE academic_session GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
          ''');
          // Rewrite current session setting if still legacy range format.
          await customStatement('''
            UPDATE app_settings
            SET value = substr(value, 1, 4)
            WHERE key = 'current_academic_session'
              AND value GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9][0-9][0-9]'
          ''');
        }

        if (from < 35) {
          await customStatement(
            'ALTER TABLE subjects ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
          );
          await _backfillSubjectSortOrders();
        }
      },
    );
  }

  /// Sets subjects.sort_order from curriculum lists; unknown subjects append after.
  Future<void> _backfillSubjectSortOrders() async {
    final classRows = await customSelect(
      "SELECT id, name FROM classes WHERE name IN ('Year 1', 'Year 2', 'Year 3')",
      readsFrom: {classes},
    ).get();
    final classIdByName = {
      for (final row in classRows) row.read<String>('name'): row.read<int>('id'),
    };
    final curriculumByClassId = <int, List<String>>{};
    final y1Id = classIdByName['Year 1'];
    final y2Id = classIdByName['Year 2'];
    final y3Id = classIdByName['Year 3'];
    if (y1Id != null) curriculumByClassId[y1Id] = SubjectCurriculumOrder.year1;
    if (y2Id != null) curriculumByClassId[y2Id] = SubjectCurriculumOrder.year2;
    if (y3Id != null) curriculumByClassId[y3Id] = SubjectCurriculumOrder.year3;

    for (final entry in curriculumByClassId.entries) {
      final classId = entry.key;
      final names = entry.value;
      for (var i = 0; i < names.length; i++) {
        final escapedName = names[i].replaceAll("'", "''");
        await customStatement('''
          UPDATE subjects
          SET sort_order = $i
          WHERE class_id = $classId AND name = '$escapedName'
        ''');
      }
      // Custom subjects not in curriculum: append after max, stable by name then id.
      final extras = await customSelect(
        '''
        SELECT id FROM subjects
        WHERE class_id = ?
          AND name NOT IN (${names.map((_) => '?').join(', ')})
        ORDER BY name COLLATE NOCASE, id
        ''',
        variables: [
          Variable.withInt(classId),
          ...names.map(Variable.withString),
        ],
        readsFrom: {subjects},
      ).get();
      var next = names.length;
      for (final row in extras) {
        final id = row.read<int>('id');
        await customStatement(
          'UPDATE subjects SET sort_order = $next WHERE id = $id',
        );
        next++;
      }
    }

    // Any other class_id not in the curriculum map: order by name then id.
    final knownIds = curriculumByClassId.keys.toList();
    final otherClasses = knownIds.isEmpty
        ? await customSelect(
            'SELECT DISTINCT class_id FROM subjects',
            readsFrom: {subjects},
          ).get()
        : await customSelect(
            '''
            SELECT DISTINCT class_id FROM subjects
            WHERE class_id NOT IN (${knownIds.map((_) => '?').join(', ')})
            ''',
            variables: knownIds.map(Variable.withInt).toList(),
            readsFrom: {subjects},
          ).get();
    for (final classRow in otherClasses) {
      final classId = classRow.read<int>('class_id');
      final rows = await customSelect(
        '''
        SELECT id FROM subjects
        WHERE class_id = ?
        ORDER BY name COLLATE NOCASE, id
        ''',
        variables: [Variable.withInt(classId)],
        readsFrom: {subjects},
      ).get();
      for (var i = 0; i < rows.length; i++) {
        final id = rows[i].read<int>('id');
        await customStatement(
          'UPDATE subjects SET sort_order = $i WHERE id = $id',
        );
      }
    }
  }

  /// Ensures there is at least a current and previous academic session row.
  /// Session = single calendar year Feb–Oct; code e.g. "2026", "2025".
  Future<void> _ensureInitialAcademicSessions() async {
    try {
      final result = await customSelect(
        'SELECT COUNT(*) AS c FROM academic_sessions',
      ).getSingle();
      final count = result.data['c'] as int? ?? 0;
      if (count > 0) {
        return;
      }
    } catch (_) {
      return;
    }

    final now = DateTime.now();
    final year = now.year;
    final currentCode = year.toString();
    final previousCode = (year - 1).toString();
    // Feb 1 and Oct 31 of each year (Unix seconds at UTC midnight).
    final currentStart = DateTime.utc(year, 2, 1).millisecondsSinceEpoch ~/ 1000;
    final currentEnd = DateTime.utc(year, 10, 31).millisecondsSinceEpoch ~/ 1000;
    final previousStart = DateTime.utc(year - 1, 2, 1).millisecondsSinceEpoch ~/ 1000;
    final previousEnd = DateTime.utc(year - 1, 10, 31).millisecondsSinceEpoch ~/ 1000;

    await customStatement(
      'INSERT OR IGNORE INTO academic_sessions (code, start_date, end_date, is_active) VALUES (?, ?, ?, 0)',
      [previousCode, previousStart, previousEnd],
    );
    await customStatement(
      'INSERT OR IGNORE INTO academic_sessions (code, start_date, end_date, is_active) VALUES (?, ?, ?, 1)',
      [currentCode, currentStart, currentEnd],
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

/// Opens a database connection from a specific file (for scripts).
LazyDatabase _openFileConnection(File file) {
  return LazyDatabase(() async {
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
