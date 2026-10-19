import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/utils/io_retry.dart';
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

/// Status of change-set sync against Neon.
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

/// Runs full Neon sync (push then pull) and updates sync status.
/// Returns number of imported/applied change-sets from other devices.
///
/// When [quietIfUnconfigured] is true, a missing connection string returns 0
/// without marking sync as failed. Startup, polling, and post-save sync use that.
Future<int> runChangeSetFullSync(
  Ref ref, {
  bool invalidateConflictCount = false,
  bool quietIfUnconfigured = false,
}) =>
    _runChangeSetFullSyncCore(
      read: ref.read,
      invalidate: ref.invalidate,
      invalidateConflictCount: invalidateConflictCount,
      quietIfUnconfigured: quietIfUnconfigured,
    );

/// Same as [runChangeSetFullSync]; use from `Consumer*` widgets because
/// [WidgetRef] is not assignable to [Ref] in Riverpod 2.x.
Future<int> runChangeSetFullSyncForWidget(
  WidgetRef ref, {
  bool invalidateConflictCount = false,
  bool quietIfUnconfigured = false,
}) =>
    _runChangeSetFullSyncCore(
      read: ref.read,
      invalidate: ref.invalidate,
      invalidateConflictCount: invalidateConflictCount,
      quietIfUnconfigured: quietIfUnconfigured,
    );

/// Serializes full sync across manual, startup, post-CRUD, and folder-watcher entry points.
final _changeSetSyncLock = _ChangeSetSyncLock();

const Duration _syncTimeout = Duration(seconds: 120);

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
  bool quietIfUnconfigured = false,
}) {
  return _changeSetSyncLock.run(() async {
    final syncService = read(changeSetSyncServiceProvider);
    if (quietIfUnconfigured && !await syncService.remoteConfigured()) {
      return 0;
    }
    final status = read(changeSetSyncStatusProvider.notifier);
    status.setSyncing(true);
    try {
      final db = read(appDatabaseProvider);
      final applier = ChangeSetApplier(db);
      final applied = await syncService.syncWithRemote(
        tryApply: (record) => applier.tryApply(record),
      ).timeout(
        _syncTimeout,
        onTimeout: () => throw TimeoutException(
          'Sync timed out after ${_syncTimeout.inSeconds}s',
        ),
      );
      status.setSuccess();
      if (invalidateConflictCount) {
        invalidate(syncConflictsCountProvider);
      }
      return applied;
    } catch (e) {
      status.setError(userFacingSyncError(e));
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
  static const _transientRetryDelay = Duration(seconds: 5);

  Timer? _debounce;
  Timer? _transientRetry;
  bool _running = false;
  bool _pendingRun = false;
  /// One delayed follow-up per CRUD-triggered failure burst (not an infinite loop).
  bool _transientRetryUsed = false;

  void schedule() {
    _transientRetryUsed = false;
    _transientRetry?.cancel();
    _transientRetry = null;
    _debounce?.cancel();
    _debounce = Timer(_debounceDuration, () {
      unawaited(_runSingleFlight());
    });
  }

  void dispose() {
    _debounce?.cancel();
    _debounce = null;
    _transientRetry?.cancel();
    _transientRetry = null;
  }

  void _scheduleTransientRetry() {
    if (_transientRetryUsed) return;
    _transientRetryUsed = true;
    _transientRetry?.cancel();
    _transientRetry = Timer(_transientRetryDelay, () {
      unawaited(_runSingleFlight());
    });
  }

  Future<void> _runSingleFlight() async {
    if (_running) {
      _pendingRun = true;
      return;
    }
    _running = true;
    Object? lastError;
    try {
      do {
        _pendingRun = false;
        lastError = null;
        try {
          await runChangeSetFullSync(_ref, quietIfUnconfigured: true);
        } catch (e) {
          lastError = e;
          // Status already updated; avoid crashing scheduler (matches folder watcher).
        }
      } while (_pendingRun);
    } finally {
      _running = false;
    }
    if (lastError != null && isTransientIoError(lastError)) {
      _scheduleTransientRetry();
    }
  }
}
