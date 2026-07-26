import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Repository for classes (academic year levels: Year 1, Year 2, Year 3).
class ClassRepository {
  ClassRepository(this._db, {void Function()? onLocalChangeSetWritten})
      : _onLocalChangeSetWritten = onLocalChangeSetWritten;

  final AppDatabase _db;
  final void Function()? _onLocalChangeSetWritten;
  static const _uuid = Uuid();

  Future<String> _effectiveChangeSetDeviceId(String? deviceId) async {
    final d = deviceId?.trim();
    if (d != null && d.isNotEmpty && d != 'legacy') return d;
    return SyncFolderConfig.getOrCreateDeviceId();
  }

  /// Stream of all classes ordered by sortOrder then name.
  Stream<List<SchoolClass>> watchClasses() {
    return (_db.select(_db.classes)
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .watch();
  }

  /// One-time fetch of all classes ordered by sortOrder then name.
  Future<List<SchoolClass>> getAllClasses() async {
    return (_db.select(_db.classes)
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .get();
  }

  /// Fetch a class by id, or null if not found.
  Future<SchoolClass?> getClassById(int id) async {
    return (_db.select(_db.classes)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Fetch a class by name (e.g. "Year 2"), or null if not found.
  Future<SchoolClass?> getClassByName(String name) async {
    return (_db.select(_db.classes)..where((t) => t.name.equals(name)))
        .getSingleOrNull();
  }

  /// Insert a new class. Returns the new row id.
  Future<int> insert(
    ClassesCompanion companion, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageUsers(userRole)) {
      throw StateError('Role cannot manage classes');
    }
    final id = await _db.into(_db.classes).insert(companion);
    if (userId != null) {
      final row = await getClassById(id);
      if (row != null) {
        await _insertChangeSet(
          table: 'classes',
          recordId: id.toString(),
          operation: 'INSERT',
          payload: await _payloadFromClass(row),
          userId: userId,
          version: 1,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: screen,
        );
      }
    }
    return id;
  }

  /// Update an existing class by id.
  Future<void> update(
    int id,
    ClassesCompanion companion, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageUsers(userRole)) {
      throw StateError('Role cannot manage classes');
    }
    await (_db.update(_db.classes)..where((t) => t.id.equals(id)))
        .write(companion);
    if (userId != null) {
      final row = await getClassById(id);
      if (row != null) {
        await _insertChangeSet(
          table: 'classes',
          recordId: id.toString(),
          operation: 'UPDATE',
          payload: await _payloadFromClass(row),
          userId: userId,
          version: 1,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: screen,
        );
      }
    }
  }

  /// Set or clear the facilitator for a class.
  Future<void> updateFacilitator(
    int classId,
    int? userId, {
    required UserRole userRole,
    String? actorUserId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageUsers(userRole)) {
      throw StateError('Role cannot manage classes');
    }
    await (_db.update(_db.classes)..where((t) => t.id.equals(classId))).write(
      ClassesCompanion(
        facilitatorUserId: Value(userId),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (actorUserId != null) {
      final row = await getClassById(classId);
      if (row != null) {
        await _insertChangeSet(
          table: 'classes',
          recordId: classId.toString(),
          operation: 'UPDATE',
          payload: await _payloadFromClass(row),
          userId: actorUserId,
          version: 1,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: screen,
        );
      }
    }
  }

  /// Classes assigned to the given facilitator (where facilitatorUserId == userId).
  Future<List<SchoolClass>> getClassesByFacilitatorUserId(int userId) async {
    return (_db.select(_db.classes)
          ..where((t) => t.facilitatorUserId.equals(userId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.sortOrder),
            (t) => OrderingTerm.asc(t.name),
          ]))
        .get();
  }

  /// Class ids assigned to the given facilitator (for scope filtering).
  Future<List<int>> getClassIdsByFacilitatorUserId(int userId) async {
    final classes = await getClassesByFacilitatorUserId(userId);
    return classes.map((c) => c.id).toList();
  }

  Future<Map<String, dynamic>> _payloadFromClass(SchoolClass row) async {
    String? facilitatorUsername;
    if (row.facilitatorUserId != null) {
      final u = await (_db.select(_db.users)
            ..where((t) => t.id.equals(row.facilitatorUserId!)))
          .getSingleOrNull();
      facilitatorUsername = u?.username;
    }
    return {
      'name': row.name,
      'sortOrder': row.sortOrder,
      if (facilitatorUsername != null) 'facilitatorUsername': facilitatorUsername,
      if (row.updatedAt != null)
        'updatedAt': row.updatedAt!.toUtc().toIso8601String(),
    };
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
