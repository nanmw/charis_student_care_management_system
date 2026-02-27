import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/change_sets_repository.dart';
import 'package:charis_student_care/data/repositories/sync_conflicts_repository.dart';
import 'package:charis_student_care/data/services/change_set_sync_service.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

/// Bootstrap config for change-set sync (sync folder path and device ID).
/// Does not depend on the main database.
final syncFolderConfigProvider =
    FutureProvider.autoDispose<SyncFolderConfig>((ref) {
  return SyncFolderConfig.load();
});

/// Device ID for this installation. Used when writing change-sets.
final deviceIdProvider = FutureProvider.autoDispose<String>((ref) {
  return SyncFolderConfig.getOrCreateDeviceId();
});

/// Stream of this device's change-sets (for pending indicator).
final changeSetsForDeviceProvider = StreamProvider.autoDispose.family<List<ChangeSet>, String>((ref, deviceId) {
  final db = ref.watch(appDatabaseProvider);
  final repo = ChangeSetsRepository(db);
  return repo.watchChangeSetsByDevice(deviceId);
});

/// Stream of unresolved conflict count (for conflict indicator).
final syncConflictsCountStreamProvider = StreamProvider.autoDispose<int>((ref) {
  final repo = ref.watch(syncConflictsRepositoryProvider);
  return repo.watchConflictCount();
});

/// Stream of unresolved conflicts list (for Settings resolve UI).
final syncConflictsListStreamProvider = StreamProvider.autoDispose<List<SyncConflict>>((ref) {
  final repo = ref.watch(syncConflictsRepositoryProvider);
  return repo.watchConflicts();
});

/// Status of change-set sync (folder-based sync). Replaces old OneDrive OAuth status.
class ChangeSetSyncStatus extends ChangeNotifier {
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  String? _lastError;

  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get lastError => _lastError;
  bool get hasError => _lastError != null && _lastError!.isNotEmpty;

  void setSyncing(bool value) {
    if (_isSyncing == value) return;
    _isSyncing = value;
    if (!value) _lastError = null;
    notifyListeners();
  }

  void setSuccess() {
    _isSyncing = false;
    _lastError = null;
    _lastSyncTime = DateTime.now();
    notifyListeners();
  }

  void setError(String message) {
    _isSyncing = false;
    _lastError = message;
    notifyListeners();
  }
}

final changeSetSyncStatusProvider =
    ChangeNotifierProvider<ChangeSetSyncStatus>((ref) {
  return ChangeSetSyncStatus();
});

/// Sync conflicts repository (for conflict resolution UI and count).
final syncConflictsRepositoryProvider = Provider<SyncConflictsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SyncConflictsRepository(db);
});

/// Unresolved conflict count (for sync status and snackbar).
final syncConflictsCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final repo = ref.watch(syncConflictsRepositoryProvider);
  return repo.count();
});

/// Change-set sync service: export/import to sync folder.
final changeSetSyncServiceProvider = Provider<ChangeSetSyncService>((ref) {
  final db = ref.watch(appDatabaseProvider);
  final changeSetsRepo = ChangeSetsRepository(db);
  final syncConflictsRepo = ref.watch(syncConflictsRepositoryProvider);
  return ChangeSetSyncService(
    changeSetsRepo: changeSetsRepo,
    syncConflictsRepo: syncConflictsRepo,
  );
});
