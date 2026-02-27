import 'package:drift/drift.dart';

import 'package:charis_student_care/data/database/app_database.dart';

/// Repository for unresolved sync conflicts (critical table clashes).
class SyncConflictsRepository {
  SyncConflictsRepository(this._db);

  final AppDatabase _db;

  /// All unresolved conflicts, newest first.
  Stream<List<SyncConflict>> watchConflicts() {
    return (_db.select(_db.syncConflicts)
          ..orderBy([(t) => OrderingTerm.desc(t.detectedAt)]))
        .watch();
  }

  /// Count of unresolved conflicts.
  Future<int> count() async {
    final list = await _db.select(_db.syncConflicts).get();
    return list.length;
  }

  /// Stream of conflict count (for sync status indicator).
  Stream<int> watchConflictCount() {
    return (_db.select(_db.syncConflicts).watch()).map((list) => list.length);
  }

  /// Insert a conflict (when import detects critical clash).
  Future<void> insert({
    required String changeSetId,
    required String tableName,
    required String recordId,
    required String incomingPayload,
    required String localSnapshot,
    required String sourceDeviceId,
  }) async {
    await _db.into(_db.syncConflicts).insert(
          SyncConflictsCompanion.insert(
            changeSetId: changeSetId,
            entityTable: tableName,
            recordId: recordId,
            incomingPayload: incomingPayload,
            localSnapshot: localSnapshot,
            detectedAt: DateTime.now(),
            sourceDeviceId: sourceDeviceId,
          ),
        );
  }

  /// Get one conflict by id.
  Future<SyncConflict?> getById(int id) async {
    return (_db.select(_db.syncConflicts)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Resolve by keeping local: just delete the conflict row.
  Future<void> resolveKeepLocal(int conflictId) async {
    await (_db.delete(_db.syncConflicts)..where((t) => t.id.equals(conflictId))).go();
  }

  /// Resolve by using incoming: apply the stored payload then delete the conflict.
  /// Caller must use [ChangeSetApplier] to apply the incoming payload (build a ChangeSetRecord from conflict).
  /// After applying, call [resolveKeepLocal] to remove the conflict row.
  /// This method only deletes the row; applying is done by the caller with the applier.
  Future<void> resolveUseIncoming(int conflictId) async {
    await (_db.delete(_db.syncConflicts)..where((t) => t.id.equals(conflictId))).go();
  }
}
