import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Subject repository: watch subjects per year, add/update/delete with change-set logging.
/// Only Admin Level 01 can manage subjects.
class SubjectRepository {
  SubjectRepository(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();

  /// Stream of subjects for [year], ordered by name alphabetically.
  Stream<List<Subject>> watchSubjectsForYear(String year) {
    return (_db.select(_db.subjects)
          ..where((t) => t.year.equals(year))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  /// One-time fetch of subjects for [year], ordered by name alphabetically.
  Future<List<Subject>> getSubjectsForYear(String year) async {
    return (_db.select(_db.subjects)
          ..where((t) => t.year.equals(year))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  /// Fetch a single subject by [id], or null if not found.
  Future<Subject?> getSubject(int id) async {
    return (_db.select(_db.subjects)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Adds a subject. Requires Admin Level 01; [userId] for change-set.
  Future<int> addSubject(
    String name,
    String year, {
    required UserRole userRole,
    String? userId,
  }) async {
    if (!RolePermissions.canManageSubjects(userRole)) {
      throw StateError('Role cannot manage subjects');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Subject name cannot be empty');
    }
    final companion = SubjectsCompanion.insert(
      name: trimmedName,
      year: year,
    );
    final id = await _db.into(_db.subjects).insert(companion);
    if (userId != null) {
      await _insertChangeSet(
        table: 'subjects',
        recordId: id.toString(),
        operation: 'INSERT',
        payload: {
          'name': trimmedName,
          'year': year,
        },
        userId: userId,
        version: 1,
      );
    }
    return id;
  }

  /// Updates a subject. Requires Admin Level 01; [userId] for change-set.
  /// Note: Year cannot be changed for existing subjects.
  Future<void> updateSubject(
    int id, {
    required String name,
    required UserRole userRole,
    String? userId,
  }) async {
    if (!RolePermissions.canManageSubjects(userRole)) {
      throw StateError('Role cannot manage subjects');
    }
    final row = await (_db.select(_db.subjects)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw StateError('Subject not found');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Subject name cannot be empty');
    }
    await (_db.update(_db.subjects)..where((t) => t.id.equals(id))).write(
      SubjectsCompanion(
        name: Value(trimmedName),
      ),
    );
    if (userId != null) {
      await _insertChangeSet(
        table: 'subjects',
        recordId: id.toString(),
        operation: 'UPDATE',
        payload: {
          'name': trimmedName,
        },
        userId: userId,
        version: 1,
      );
    }
  }

  /// Deletes a subject. Requires Admin Level 01; [userId] for change-set.
  Future<void> deleteSubject(
    int id, {
    required UserRole userRole,
    String? userId,
  }) async {
    if (!RolePermissions.canManageSubjects(userRole)) {
      throw StateError('Role cannot manage subjects');
    }
    final row = await (_db.select(_db.subjects)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw StateError('Subject not found');
    }
    await (_db.delete(_db.subjects)..where((t) => t.id.equals(id))).go();
    if (userId != null) {
      await _insertChangeSet(
        table: 'subjects',
        recordId: id.toString(),
        operation: 'DELETE',
        payload: {
          'name': row.name,
          'year': row.year,
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
