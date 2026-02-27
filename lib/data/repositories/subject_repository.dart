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

  /// Stream of subjects for [classId], ordered by name alphabetically.
  Stream<List<Subject>> watchSubjectsForClass(int classId) {
    return (_db.select(_db.subjects)
          ..where((t) => t.classId.equals(classId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  /// One-time fetch of subjects for [classId], ordered by name alphabetically.
  Future<List<Subject>> getSubjectsForClass(int classId) async {
    return (_db.select(_db.subjects)
          ..where((t) => t.classId.equals(classId))
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .get();
  }

  /// Fetch a single subject by [id], or null if not found.
  Future<Subject?> getSubject(int id) async {
    return (_db.select(_db.subjects)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Adds a subject. Requires Admin Level 01; [userId], [deviceId], [userDisplayName], [screen] for change-set.
  Future<int> addSubject(
    String name,
    int classId, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
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
      classId: classId,
    );
    final id = await _db.into(_db.subjects).insert(companion);
    if (userId != null) {
      await _insertChangeSet(
        table: 'subjects',
        recordId: id.toString(),
        operation: 'INSERT',
        payload: {
          'name': trimmedName,
          'classId': classId,
          if (userDisplayName != null) 'userDisplayName': userDisplayName,
          if (screen != null) 'screen': screen,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId ?? 'legacy',
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
    return id;
  }

  /// Updates a subject. Requires Admin Level 01; [userId], [userDisplayName], [screen] for change-set.
  /// Note: Year cannot be changed for existing subjects.
  Future<void> updateSubject(
    int id, {
    required String name,
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
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
          if (userDisplayName != null) 'userDisplayName': userDisplayName,
          if (screen != null) 'screen': screen,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId ?? 'legacy',
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  /// Deletes a subject. Requires Admin Level 01; [userId], [userDisplayName], [screen] for change-set.
  Future<void> deleteSubject(
    int id, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
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
          'classId': row.classId,
          if (userDisplayName != null) 'userDisplayName': userDisplayName,
          if (screen != null) 'screen': screen,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId ?? 'legacy',
        userDisplayName: userDisplayName,
        screen: screen,
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
