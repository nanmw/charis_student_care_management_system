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

  /// Adds a test. Requires canEnterTests; [userId] for change-set.
  Future<int> addTest(
    int studentId,
    int score, {
    String? label,
    required UserRole userRole,
    String? userId,
  }) async {
    if (!RolePermissions.canEnterTests(userRole)) {
      throw StateError('Role cannot enter tests');
    }
    final clampedScore = score.clamp(0, 100);
    final companion = TestsCompanion.insert(
      studentId: studentId,
      score: clampedScore,
      label: (label != null && label.trim().isNotEmpty)
          ? Value(label.trim())
          : const Value.absent(),
    );
    final id = await _db.into(_db.tests).insert(companion);
    if (userId != null) {
      await _insertChangeSet(
        table: 'tests',
        recordId: id.toString(),
        operation: 'INSERT',
        payload: {
          'studentId': studentId,
          'score': clampedScore,
          if (label != null && label.trim().isNotEmpty) 'label': label.trim(),
        },
        userId: userId,
        version: 1,
      );
    }
    return id;
  }

  /// Updates a test. Requires canEnterTests; [userId] for change-set.
  Future<void> updateTest(
    int id, {
    required int score,
    String? label,
    required UserRole userRole,
    String? userId,
  }) async {
    if (!RolePermissions.canEnterTests(userRole)) {
      throw StateError('Role cannot enter tests');
    }
    final row = await (_db.select(_db.tests)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final clampedScore = score.clamp(0, 100);
    await (_db.update(_db.tests)..where((t) => t.id.equals(id))).write(
      TestsCompanion(
        score: Value(clampedScore),
        label: label != null
            ? Value(label.trim().isEmpty ? null : label.trim())
            : const Value.absent(),
      ),
    );
    if (userId != null) {
      await _insertChangeSet(
        table: 'tests',
        recordId: id.toString(),
        operation: 'UPDATE',
        payload: {
          'score': clampedScore,
          if (label != null) 'label': label.trim().isEmpty ? null : label.trim(),
        },
        userId: userId,
        version: 1,
      );
    }
  }

  Future<void> _insertChangeSet({
    required String table,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    required String userId,
    required int version,
  }) async {
    await _db.into(_db.changeSets).insert(
          ChangeSetsCompanion.insert(
            id: _uuid.v4(),
            table: table,
            recordId: recordId,
            operation: operation,
            payload: jsonEncode(payload),
            userId: userId,
            version: version,
          ),
        );
  }
}
