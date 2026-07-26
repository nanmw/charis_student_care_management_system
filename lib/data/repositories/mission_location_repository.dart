import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Mission location repository: watch locations, add/update/delete with change-set logging.
/// Only users with canManageMissions can manage locations.
class MissionLocationRepository {
  MissionLocationRepository(
    this._db, {
    void Function()? onLocalChangeSetWritten,
  }) : _onLocalChangeSetWritten = onLocalChangeSetWritten;

  final AppDatabase _db;
  final void Function()? _onLocalChangeSetWritten;
  static const _uuid = Uuid();

  Future<String> _effectiveChangeSetDeviceId(String? deviceId) async {
    final d = deviceId?.trim();
    if (d != null && d.isNotEmpty && d != 'legacy') return d;
    return SyncFolderConfig.getOrCreateDeviceId();
  }

  /// Stream of all mission locations, ordered by name.
  Stream<List<MissionLocation>> watchMissionLocations() {
    return (_db.select(_db.missionLocations)
          ..orderBy([(t) => OrderingTerm.asc(t.name)]))
        .watch();
  }

  /// Fetch a single location by [id], or null if not found.
  Future<MissionLocation?> getMissionLocation(int id) async {
    return (_db.select(_db.missionLocations)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Adds a mission location. Requires canManageMissions.
  Future<int> addMissionLocation(
    String name, {
    String? description,
    bool isActive = true,
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageMissions(userRole)) {
      throw StateError('Role cannot manage mission locations');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Location name cannot be empty');
    }
    final companion = MissionLocationsCompanion.insert(
      name: trimmedName,
      description: Value(
          description?.trim().isEmpty ?? true ? null : description?.trim(),),
      isActive: Value(isActive),
    );
    final id = await _db.into(_db.missionLocations).insert(companion);
    if (userId != null) {
      await _insertChangeSet(
        table: 'mission_locations',
        recordId: id.toString(),
        operation: 'INSERT',
        payload: {
          'name': trimmedName,
          if (description != null) 'description': description,
          'isActive': isActive,
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

  /// Updates a mission location. Requires canManageMissions.
  Future<void> updateMissionLocation(
    int id, {
    required String name,
    String? description,
    bool? isActive,
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageMissions(userRole)) {
      throw StateError('Role cannot manage mission locations');
    }
    final row = await (_db.select(_db.missionLocations)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Mission location not found');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Location name cannot be empty');
    }
    await (_db.update(_db.missionLocations)..where((t) => t.id.equals(id)))
        .write(
      MissionLocationsCompanion(
        name: Value(trimmedName),
        description: Value(
            description?.trim().isEmpty ?? true ? null : description?.trim(),),
        isActive: isActive != null ? Value(isActive) : const Value.absent(),
      ),
    );
    if (userId != null) {
      await _insertChangeSet(
        table: 'mission_locations',
        recordId: id.toString(),
        operation: 'UPDATE',
        payload: {
          'name': trimmedName,
          if (description != null) 'description': description,
          if (isActive != null) 'isActive': isActive,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  /// Deletes a mission location. Requires canManageMissions.
  Future<void> deleteMissionLocation(
    int id, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageMissions(userRole)) {
      throw StateError('Role cannot manage mission locations');
    }
    final row = await (_db.select(_db.missionLocations)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('Mission location not found');
    }
    await (_db.delete(_db.missionLocations)..where((t) => t.id.equals(id)))
        .go();
    if (userId != null) {
      await _insertChangeSet(
        table: 'mission_locations',
        recordId: id.toString(),
        operation: 'DELETE',
        payload: {
          'name': row.name,
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
    if (userDisplayName != null) {
      fullPayload['userDisplayName'] = userDisplayName;
    }
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
