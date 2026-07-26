import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Direction for [SubjectRepository.moveSubject].
enum SubjectMoveDirection { up, down }

/// Subject repository: watch subjects per year, add/update/delete with change-set logging.
/// Only Admin Level 01 can manage subjects.
class SubjectRepository {
  SubjectRepository(this._db, {void Function()? onLocalChangeSetWritten})
      : _onLocalChangeSetWritten = onLocalChangeSetWritten;

  final AppDatabase _db;
  final void Function()? _onLocalChangeSetWritten;
  static const _uuid = Uuid();

  Future<String> _effectiveChangeSetDeviceId(String? deviceId) async {
    final d = deviceId?.trim();
    if (d != null && d.isNotEmpty && d != 'legacy') return d;
    return SyncFolderConfig.getOrCreateDeviceId();
  }

  /// Stream of subjects for [classId], ordered by curriculum [sortOrder] then name.
  Stream<List<Subject>> watchSubjectsForClass(int classId) {
    return (_db.select(_db.subjects)
          ..where((t) => t.classId.equals(classId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .watch();
  }

  /// One-time fetch of subjects for [classId], ordered by curriculum [sortOrder] then name.
  Future<List<Subject>> getSubjectsForClass(int classId) async {
    return (_db.select(_db.subjects)
          ..where((t) => t.classId.equals(classId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .get();
  }

  /// Fetch a single subject by [id], or null if not found.
  Future<Subject?> getSubject(int id) async {
    return (_db.select(_db.subjects)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  Future<int> _nextSortOrderForClass(int classId) async {
    final max = await _maxSortOrderForClass(classId);
    return (max ?? -1) + 1;
  }

  Future<int?> _maxSortOrderForClass(int classId) async {
    final result = await _db.customSelect(
      'SELECT MAX(sort_order) AS m FROM subjects WHERE class_id = ?',
      variables: [Variable.withInt(classId)],
      readsFrom: {_db.subjects},
    ).getSingleOrNull();
    if (result == null) return null;
    return result.readNullable<int>('m');
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
    final sortOrder = await _nextSortOrderForClass(classId);
    final companion = SubjectsCompanion.insert(
      name: trimmedName,
      classId: classId,
      sortOrder: Value(sortOrder),
    );
    final id = await _db.into(_db.subjects).insert(companion);
    if (userId != null) {
      final classRow = await (_db.select(_db.classes)
            ..where((t) => t.id.equals(classId)))
          .getSingleOrNull();
      await _insertChangeSet(
        table: 'subjects',
        recordId: id.toString(),
        operation: 'INSERT',
        payload: {
          'name': trimmedName,
          'classId': classId,
          'sortOrder': sortOrder,
          if (classRow != null) 'className': classRow.name,
          if (userDisplayName != null) 'userDisplayName': userDisplayName,
          if (screen != null) 'screen': screen,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId,
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
          'sortOrder': row.sortOrder,
          if (userDisplayName != null) 'userDisplayName': userDisplayName,
          if (screen != null) 'screen': screen,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  /// Swaps [sortOrder] with the adjacent subject in the same class.
  Future<void> moveSubject(
    int id,
    SubjectMoveDirection direction, {
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
    final ordered = await getSubjectsForClass(row.classId);
    final index = ordered.indexWhere((s) => s.id == id);
    if (index < 0) {
      throw StateError('Subject not found in class');
    }
    final swapIndex = direction == SubjectMoveDirection.up ? index - 1 : index + 1;
    if (swapIndex < 0 || swapIndex >= ordered.length) {
      return;
    }
    final other = ordered[swapIndex];
    final aOrder = row.sortOrder;
    final bOrder = other.sortOrder;
    await _db.transaction(() async {
      await (_db.update(_db.subjects)..where((t) => t.id.equals(row.id))).write(
            SubjectsCompanion(sortOrder: Value(bOrder)),
          );
      await (_db.update(_db.subjects)..where((t) => t.id.equals(other.id))).write(
            SubjectsCompanion(sortOrder: Value(aOrder)),
          );
    });
    if (userId != null) {
      await _insertChangeSet(
        table: 'subjects',
        recordId: row.id.toString(),
        operation: 'UPDATE',
        payload: {
          'name': row.name,
          'sortOrder': bOrder,
          if (userDisplayName != null) 'userDisplayName': userDisplayName,
          if (screen != null) 'screen': screen,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: screen,
      );
      await _insertChangeSet(
        table: 'subjects',
        recordId: other.id.toString(),
        operation: 'UPDATE',
        payload: {
          'name': other.name,
          'sortOrder': aOrder,
          if (userDisplayName != null) 'userDisplayName': userDisplayName,
          if (screen != null) 'screen': screen,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId,
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
      final classRow = await (_db.select(_db.classes)
            ..where((t) => t.id.equals(row.classId)))
          .getSingleOrNull();
      await _insertChangeSet(
        table: 'subjects',
        recordId: id.toString(),
        operation: 'DELETE',
        payload: {
          'name': row.name,
          'classId': row.classId,
          'sortOrder': row.sortOrder,
          if (classRow != null) 'className': classRow.name,
          if (userDisplayName != null) 'userDisplayName': userDisplayName,
          if (screen != null) 'screen': screen,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId,
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
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    final effectiveDeviceId = await _effectiveChangeSetDeviceId(deviceId);
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
            deviceId: effectiveDeviceId,
          ),
        );
    _onLocalChangeSetWritten?.call();
  }
}
