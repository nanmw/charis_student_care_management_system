import 'package:drift/drift.dart';

import 'package:charis_student_care/data/database/app_database.dart';

/// Change sets repository: watch recent changes for activity feed.
class ChangeSetsRepository {
  ChangeSetsRepository(this._db);

  final AppDatabase _db;

  /// Stream of recent change sets, ordered by timestamp descending.
  /// Returns the [limit] most recent changes.
  Stream<List<ChangeSet>> watchRecentChanges({int limit = 10}) {
    return (_db.select(_db.changeSets)
          ..orderBy([(t) => OrderingTerm.desc(t.timestamp)])
          ..limit(limit))
        .watch();
  }

  /// All change-sets for the given [deviceId], ordered by timestamp ascending (for export).
  Future<List<ChangeSet>> getChangeSetsByDevice(String deviceId) async {
    return (_db.select(_db.changeSets)
          ..where((t) => t.deviceId.equals(deviceId))
          ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
        .get();
  }

  /// Stream of this device's change-sets (for pending-status: any after [afterTime] = pending).
  Stream<List<ChangeSet>> watchChangeSetsByDevice(String deviceId) {
    return (_db.select(_db.changeSets)
          ..where((t) => t.deviceId.equals(deviceId))
          ..orderBy([(t) => OrderingTerm.asc(t.timestamp)]))
        .watch();
  }

  /// Rewrites `device_id = 'legacy'` to [deviceId] so local edits export with this installation.
  Future<int> retagLegacyChangeSetsTo(String deviceId) async {
    return (_db.update(_db.changeSets)..where((t) => t.deviceId.equals('legacy')))
        .write(ChangeSetsCompanion(deviceId: Value(deviceId)));
  }

  /// Returns true if a change-set with the given [id] exists (for import dedupe).
  Future<bool> hasChangeSet(String id) async {
    final row = await (_db.select(_db.changeSets)
          ..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row != null;
  }

  /// Insert a change-set without applying (e.g. when deferred due to conflict).
  Future<void> insertChangeSetRaw({
    required String id,
    required String table,
    required String recordId,
    required String operation,
    required String payload,
    required DateTime timestamp,
    required String userId,
    required int version,
    required String deviceId,
  }) async {
    await _db.into(_db.changeSets).insert(
          ChangeSetsCompanion.insert(
            id: id,
            table: table,
            recordId: recordId,
            operation: operation,
            payload: payload,
            timestamp: Value(timestamp),
            userId: userId,
            version: version,
            deviceId: deviceId,
          ),
        );
  }
}
