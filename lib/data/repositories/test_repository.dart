import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Test repository: watch tests per student, add/update with change-set logging.
/// Outstanding = count where score < 70. All roles can enter tests.
class TestRepository {
  TestRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  static const int _passThreshold = 70;

  Future<String?> _classNameForId(int? classId) async {
    if (classId == null) return null;
    final c = await (_db.select(_db.classes)..where((c) => c.id.equals(classId))).getSingleOrNull();
    return c?.name;
  }

  static Map<String, dynamic> _studentYearEntry(String? name) =>
      (name != null && name.isNotEmpty) ? {'studentYear': name} : {};

  /// Stream of all tests, ordered by studentId and createdAt desc.
  Stream<List<Test>> watchAllTests() {
    return (_db.select(_db.tests)
          ..orderBy([(t) => OrderingTerm.asc(t.studentId), (t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Stream of tests for [studentId], newest first.
  Stream<List<Test>> watchTestsForStudent(int studentId) {
    return (_db.select(_db.tests)
          ..where((t) => t.studentId.equals(studentId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  /// Outstanding count for one student (tests with score < 70).
  Future<int> getOutstandingCountForStudent(int studentId) async {
    final result = await (_db.selectOnly(_db.tests)
          ..addColumns([_db.tests.id.count()])
          ..where(_db.tests.studentId.equals(studentId) & _db.tests.score.isSmallerThanValue(_passThreshold)))
        .getSingle();
    return result.read(_db.tests.id.count()) ?? 0;
  }

  /// Total outstanding count across all tests (score < 70).
  /// Used for dashboard.
  Future<int> getTotalOutstandingCount() async {
    final result = await (_db.selectOnly(_db.tests)
          ..addColumns([_db.tests.id.count()])
          ..where(_db.tests.score.isSmallerThanValue(_passThreshold)))
        .getSingle();
    return result.read(_db.tests.id.count()) ?? 0;
  }

  /// Stream of total outstanding count (for reactive dashboard).
  Stream<int> watchTotalOutstandingCount() {
    return (_db.selectOnly(_db.tests)
          ..addColumns([_db.tests.id.count()])
          ..where(_db.tests.score.isSmallerThanValue(_passThreshold)))
        .watch()
        .map((rows) => rows.isNotEmpty ? (rows.single.read(_db.tests.id.count()) ?? 0) : 0);
  }

  /// Finds the most recent passing test (score >= 70) for a student and subject (and optional session).
  /// When [academicSession] is null, matches any session (legacy). Returns null if no passing test exists.
  Future<Test?> findPassingTestForStudentAndSubject(
    int studentId,
    int? subjectId, {
    String? academicSession,
  }) async {
    if (subjectId == null) return null;
    var query = _db.select(_db.tests)
      ..where((t) {
        var pred = t.studentId.equals(studentId) &
            t.subjectId.equals(subjectId) &
            t.score.isBiggerOrEqualValue(_passThreshold);
        if (academicSession != null) {
          pred = pred & t.academicSession.equals(academicSession);
        }
        return pred;
      })
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(1);
    final tests = await query.get();
    return tests.isEmpty ? null : tests.first;
  }

  /// Finds the most recent test (any score) for student, subject, and session.
  /// Used to detect rewrite: existing test with score < 70 in same session.
  Future<Test?> findTestForStudentSubjectSession(
    int studentId,
    int subjectId,
    String? academicSession,
  ) async {
    var query = _db.select(_db.tests)
      ..where((t) {
        var pred = t.studentId.equals(studentId) & t.subjectId.equals(subjectId);
        if (academicSession != null) {
          pred = pred & t.academicSession.equals(academicSession);
        } else {
          pred = pred & t.academicSession.isNull();
        }
        return pred;
      })
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt), (t) => OrderingTerm.desc(t.createdAt)])
      ..limit(1);
    final tests = await query.get();
    return tests.isEmpty ? null : tests.first;
  }

  /// Returns dates (UTC midnight) on which any test was created or updated, optionally for [academicSession].
  Future<Set<DateTime>> getDatesWithTestChanges({String? academicSession}) async {
    var query = _db.select(_db.tests);
    if (academicSession != null && academicSession.trim().isNotEmpty) {
      query = query..where((t) => t.academicSession.equals(academicSession.trim()));
    }
    final tests = await query.get();
    final dates = <DateTime>{};
    for (final t in tests) {
      final created = DateTime(t.createdAt.year, t.createdAt.month, t.createdAt.day);
      dates.add(created);
      if (t.updatedAt != null) {
        final updated = DateTime(t.updatedAt!.year, t.updatedAt!.month, t.updatedAt!.day);
        dates.add(updated);
      }
    }
    return dates;
  }

  // getAcademicSessionOptions() has been moved to AcademicSessionRepository
  // Use academicSessionOptionsProvider from academic_session_providers.dart instead

  /// Adds a test. Requires canEnterTests; [userId], [userDisplayName], [screen] for change-set.
  /// [academicSession] optional; when set, enforces one passing test per session and rewrite cap.
  /// Prevents duplicate passing tests per (student, subject, session). Rewrite (second test after fail) capped at 70.
  Future<int> addTest(
    int studentId,
    int score, {
    String? label,
    int? subjectId,
    String? academicSession,
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canEnterTests(userRole)) {
      throw StateError('Role cannot enter tests');
    }
    final clampedScore = score.clamp(0, 100);

    // Duplicate passing rule (guideline 5): no two passing tests for same student, subject, session
    if (clampedScore >= _passThreshold && subjectId != null && academicSession != null) {
      final existingPassing = await findPassingTestForStudentAndSubject(
        studentId,
        subjectId,
        academicSession: academicSession,
      );
      if (existingPassing != null) {
        throw StateError(
          'A passing test already exists for this student, subject, and academic session. Please update the existing test instead.',
        );
      }
    }

    // Rewrite rule (guidelines 6 & 7): if existing test for same student+subject+session with score < 70, cap at 70
    int effectiveScore = clampedScore;
    if (subjectId != null && academicSession != null) {
      final existing = await findTestForStudentSubjectSession(
        studentId,
        subjectId,
        academicSession,
      );
      if (existing != null && existing.score < _passThreshold) {
        effectiveScore = clampedScore > _passThreshold ? _passThreshold : clampedScore;
      }
    }

    final companion = TestsCompanion.insert(
      studentId: studentId,
      score: effectiveScore,
      label: (label != null && label.trim().isNotEmpty)
          ? Value(label.trim())
          : const Value.absent(),
      subjectId: subjectId != null ? Value(subjectId) : const Value.absent(),
      createdAt: Value(DateTime.now()),
      academicSession: academicSession != null && academicSession.trim().isNotEmpty
          ? Value(academicSession.trim())
          : const Value.absent(),
    );
    final id = await _db.into(_db.tests).insert(companion);
    if (userId != null) {
      final studentRow = await (_db.select(_db.students)..where((t) => t.id.equals(studentId))).getSingleOrNull();
      final payload = <String, dynamic>{
        'studentId': studentId,
        'score': effectiveScore,
        if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
        if (subjectId != null) 'subjectId': subjectId,
        if (academicSession != null) 'academicSession': academicSession,
        if (studentRow != null) 'studentName': '${studentRow.surname}, ${studentRow.firstName}',
        if (studentRow != null) ..._studentYearEntry(await _classNameForId(studentRow.classId)),
        if (studentRow != null && studentRow.mode != null && studentRow.mode!.isNotEmpty) 'studentMode': studentRow.mode,
        if (userDisplayName != null) 'userDisplayName': userDisplayName,
        if (screen != null) 'screen': screen,
      };
      await _insertChangeSet(
        table: 'tests',
        recordId: id.toString(),
        operation: 'INSERT',
        payload: payload,
        userId: userId,
        version: 1,
        deviceId: deviceId ?? 'legacy',
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
    return id;
  }

  /// Updates a test. Requires canEnterTests; [userId], [userDisplayName], [screen] for change-set.
  /// Does not clear [academicSession]; existing session is preserved.
  Future<void> updateTest(
    int id, {
    required int score,
    String? label,
    int? subjectId,
    String? academicSession,
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canEnterTests(userRole)) {
      throw StateError('Role cannot enter tests');
    }
    final row = await (_db.select(_db.tests)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final clampedScore = score.clamp(0, 100);
    final companion = TestsCompanion(
      score: Value(clampedScore),
      label: label != null
          ? Value(label.trim().isEmpty ? null : label.trim())
          : const Value.absent(),
      subjectId: subjectId != null ? Value(subjectId) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
      academicSession: academicSession != null
          ? Value(academicSession.trim().isEmpty ? null : academicSession.trim())
          : const Value.absent(),
    );
    await (_db.update(_db.tests)..where((t) => t.id.equals(id))).write(companion);
    if (userId != null) {
      final studentRow = await (_db.select(_db.students)..where((t) => t.id.equals(row.studentId))).getSingleOrNull();
      final payload = <String, dynamic>{
        'studentId': row.studentId,
        'score': clampedScore,
        if (label != null) 'label': label.trim().isEmpty ? null : label.trim(),
        if (subjectId != null) 'subjectId': subjectId,
        if (academicSession != null) 'academicSession': academicSession,
        if (studentRow != null) 'studentName': '${studentRow.surname}, ${studentRow.firstName}',
        if (studentRow != null) ..._studentYearEntry(await _classNameForId(studentRow.classId)),
        if (studentRow != null && studentRow.mode != null && studentRow.mode!.isNotEmpty) 'studentMode': studentRow.mode,
        if (userDisplayName != null) 'userDisplayName': userDisplayName,
        if (screen != null) 'screen': screen,
      };
      await _insertChangeSet(
        table: 'tests',
        recordId: id.toString(),
        operation: 'UPDATE',
        payload: payload,
        userId: userId,
        version: 1,
        deviceId: deviceId ?? 'legacy',
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  /// Deletes a test. Requires canEnterTests; [userId], [userDisplayName], [screen] for change-set.
  Future<void> deleteTest(
    int id, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canEnterTests(userRole)) {
      throw StateError('Role cannot enter tests');
    }
    final row = await (_db.select(_db.tests)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    
    await (_db.delete(_db.tests)..where((t) => t.id.equals(id))).go();
    
    if (userId != null) {
      final studentRow = await (_db.select(_db.students)..where((t) => t.id.equals(row.studentId))).getSingleOrNull();
      final payload = <String, dynamic>{
        'studentId': row.studentId,
        'score': row.score,
        if (row.label != null) 'label': row.label,
        if (row.subjectId != null) 'subjectId': row.subjectId,
        if (studentRow != null) 'studentName': '${studentRow.surname}, ${studentRow.firstName}',
        if (studentRow != null) ..._studentYearEntry(await _classNameForId(studentRow.classId)),
        if (studentRow != null && studentRow.mode != null && studentRow.mode!.isNotEmpty) 'studentMode': studentRow.mode,
        if (userDisplayName != null) 'userDisplayName': userDisplayName,
        if (screen != null) 'screen': screen,
      };
      await _insertChangeSet(
        table: 'tests',
        recordId: id.toString(),
        operation: 'DELETE',
        payload: payload,
        userId: userId,
        version: 1,
        deviceId: deviceId ?? 'legacy',
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  /// Clears all test records from the database. Requires canEnterTests; [userId], [userDisplayName], [screen] for change-set.
  /// This is a destructive operation that removes all test data.
  Future<void> clearAllTests({
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canEnterTests(userRole)) {
      throw StateError('Role cannot enter tests');
    }
    
    // Get count before deletion for change-set logging
    final count = await (_db.selectOnly(_db.tests)..addColumns([_db.tests.id.count()])).getSingle();
    final totalCount = count.read(_db.tests.id.count()) ?? 0;
    
    // Delete all test records
    await (_db.delete(_db.tests)).go();
    
    // Log a single change-set for the bulk delete operation
    if (userId != null && totalCount > 0) {
      final payload = <String, dynamic>{
        'count': totalCount,
        if (userDisplayName != null) 'userDisplayName': userDisplayName,
        if (screen != null) 'screen': screen,
      };
      await _insertChangeSet(
        table: 'tests',
        recordId: 'all',
        operation: 'DELETE',
        payload: payload,
        userId: userId,
        version: 1,
        deviceId: deviceId ?? 'legacy',
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  /// Bulk update subject for multiple students.
  /// Creates or updates test records for each student with the specified subject.
  /// Requires canEnterTests; [userId], [userDisplayName], [screen] for change-set.
  Future<void> bulkUpdateSubjectForStudents(
    List<int> studentIds,
    int? subjectId, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canEnterTests(userRole)) {
      throw StateError('Role cannot enter tests');
    }
    if (studentIds.isEmpty) return;

    // Get existing tests for these students
    final existingTests = await (_db.select(_db.tests)
          ..where((t) => t.studentId.isIn(studentIds)))
        .get();

    final testMap = <int, Test>{};
    for (final test in existingTests) {
      // Use the most recent test for each student
      if (!testMap.containsKey(test.studentId) ||
          test.createdAt.isAfter(testMap[test.studentId]!.createdAt)) {
        testMap[test.studentId] = test;
      }
    }

    // Update or create tests
    for (final studentId in studentIds) {
      final existingTest = testMap[studentId];
      if (existingTest != null) {
        // Update existing test
        await (_db.update(_db.tests)..where((t) => t.id.equals(existingTest.id))).write(
          TestsCompanion(
            subjectId: subjectId != null ? Value(subjectId) : const Value.absent(),
            updatedAt: Value(DateTime.now()),
          ),
        );
        if (userId != null) {
          final studentRow = await (_db.select(_db.students)..where((t) => t.id.equals(studentId))).getSingleOrNull();
          final payload = <String, dynamic>{
            'studentId': studentId,
            'score': existingTest.score,
            if (existingTest.label != null) 'label': existingTest.label,
            if (subjectId != null) 'subjectId': subjectId,
            if (studentRow != null) 'studentName': '${studentRow.surname}, ${studentRow.firstName}',
            if (studentRow != null) ..._studentYearEntry(await _classNameForId(studentRow.classId)),
            if (studentRow != null && studentRow.mode != null && studentRow.mode!.isNotEmpty) 'studentMode': studentRow.mode,
            if (userDisplayName != null) 'userDisplayName': userDisplayName,
            if (screen != null) 'screen': screen,
          };
          await _insertChangeSet(
            table: 'tests',
            recordId: existingTest.id.toString(),
            operation: 'UPDATE',
            payload: payload,
            userId: userId,
            version: 1,
            deviceId: deviceId ?? 'legacy',
            userDisplayName: userDisplayName,
            screen: screen,
          );
        }
      } else {
        // Create new test with default score of 0
        final companion = TestsCompanion.insert(
          studentId: studentId,
          score: 0,
          subjectId: subjectId != null ? Value(subjectId) : const Value.absent(),
          createdAt: Value(DateTime.now()),
        );
        final id = await _db.into(_db.tests).insert(companion);
        if (userId != null) {
          final studentRow = await (_db.select(_db.students)..where((t) => t.id.equals(studentId))).getSingleOrNull();
          final payload = <String, dynamic>{
            'studentId': studentId,
            'score': 0,
            if (subjectId != null) 'subjectId': subjectId,
            if (studentRow != null) 'studentName': '${studentRow.surname}, ${studentRow.firstName}',
            if (studentRow != null) ..._studentYearEntry(await _classNameForId(studentRow.classId)),
            if (studentRow != null && studentRow.mode != null && studentRow.mode!.isNotEmpty) 'studentMode': studentRow.mode,
            if (userDisplayName != null) 'userDisplayName': userDisplayName,
            if (screen != null) 'screen': screen,
          };
          await _insertChangeSet(
            table: 'tests',
            recordId: id.toString(),
            operation: 'INSERT',
            payload: payload,
            userId: userId,
            version: 1,
            deviceId: deviceId ?? 'legacy',
            userDisplayName: userDisplayName,
            screen: screen,
          );
        }
      }
    }
  }

  Future<void> _insertChangeSet({
    required String table,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    required String userId,
    required int version,
    required String deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    final fullPayload = Map<String, dynamic>.from(payload);
    if (userDisplayName != null) fullPayload['userDisplayName'] = userDisplayName;
    if (screen != null) fullPayload['screen'] = screen;
    await _db.into(_db.changeSets).insert(
      ChangeSetsCompanion.insert(
        id: _uuid.v4(),
        table: table,
        recordId: recordId,
        operation: operation,
        payload: jsonEncode(fullPayload),
        userId: userId,
        version: version,
        deviceId: deviceId,
      ),
    );
  }
}
