import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/change_sets_repository.dart';
import 'package:charis_student_care/data/repositories/sync_conflicts_repository.dart';
import 'package:charis_student_care/data/services/change_set_applier.dart';
import 'package:charis_student_care/data/services/change_set_sync_service.dart';
import 'package:charis_student_care/presentation/providers/database_provider.dart';

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

/// Runs full folder-based sync (export then import) and updates sync status.
/// Returns number of imported/applied change-sets from other devices.
Future<int> runChangeSetFullSync(
  Ref ref, {
  bool invalidateConflictCount = false,
}) =>
    _runChangeSetFullSyncCore(
      read: ref.read,
      invalidate: ref.invalidate,
      invalidateConflictCount: invalidateConflictCount,
    );

/// Same as [runChangeSetFullSync]; use from `Consumer*` widgets because
/// [WidgetRef] is not assignable to [Ref] in Riverpod 2.x.
Future<int> runChangeSetFullSyncForWidget(
  WidgetRef ref, {
  bool invalidateConflictCount = false,
}) =>
    _runChangeSetFullSyncCore(
      read: ref.read,
      invalidate: ref.invalidate,
      invalidateConflictCount: invalidateConflictCount,
    );

/// Serializes full sync across manual, startup, post-CRUD, and folder-watcher entry points.
final _changeSetSyncLock = _ChangeSetSyncLock();

const Duration _syncExportTimeout = Duration(seconds: 60);
const Duration _syncImportTimeout = Duration(seconds: 60);

class _ChangeSetSyncLock {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.completeError(e, st);
        }
      }
    });
    return completer.future;
  }
}

Future<int> _runChangeSetFullSyncCore({
  required T Function<T>(ProviderListenable<T> provider) read,
  required void Function(ProviderOrFamily provider) invalidate,
  bool invalidateConflictCount = false,
}) {
  return _changeSetSyncLock.run(() async {
    final status = read(changeSetSyncStatusProvider.notifier);
    status.setSyncing(true);
    try {
      final syncService = read(changeSetSyncServiceProvider);
      final db = read(appDatabaseProvider);
      final applier = ChangeSetApplier(db);
      await syncService.export().timeout(
        _syncExportTimeout,
        onTimeout: () => throw TimeoutException(
          'Export timed out after ${_syncExportTimeout.inSeconds}s',
        ),
      );
      final applied = await syncService.import(
        tryApply: (record) => applier.tryApply(record),
      ).timeout(
        _syncImportTimeout,
        onTimeout: () => throw TimeoutException(
          'Import timed out after ${_syncImportTimeout.inSeconds}s',
        ),
      );
      status.setSuccess();
      if (invalidateConflictCount) {
        invalidate(syncConflictsCountProvider);
      }
      return applied;
    } catch (e) {
      status.setError(e.toString());
      rethrow;
    }
  });
}

/// Debounced full sync after local CRUD (change-set writes). Coalesces bursts;
/// single-flight with one follow-up if scheduled while a run is in progress.
final postCrudSyncSchedulerProvider = Provider<PostCrudSyncScheduler>((ref) {
  final scheduler = PostCrudSyncScheduler(ref);
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

class PostCrudSyncScheduler {
  PostCrudSyncScheduler(this._ref);

  final Ref _ref;
  static const _debounceDuration = Duration(milliseconds: 750);

  Timer? _debounce;
  bool _running = false;
  bool _pendingRun = false;

  void schedule() {
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      unawaited(_runSingleFlight());
    });
  }

  void dispose() {
    _debounce?.cancel();
    _debounce = null;
  }

  Future<void> _runSingleFlight() async {
    if (_running) {
      _pendingRun = true;
      return;
    }
    _running = true;
    try {
      do {
        _pendingRun = false;
        try {
          await runChangeSetFullSync(_ref);
        } catch (_) {
          // Status already updated; avoid crashing scheduler (matches folder watcher).
        }
      } while (_pendingRun);
    } finally {
      _running = false;
    }
  }
}
