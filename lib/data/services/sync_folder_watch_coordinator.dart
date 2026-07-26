import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef SyncRunCallback = Future<void> Function();

class SyncFolderWatchCoordinator {
  SyncFolderWatchCoordinator({
    required SyncRunCallback onSyncRequested,
    Duration debounceDuration = const Duration(seconds: 3),
    Duration postSyncCooldown = const Duration(seconds: 15),
    Stream<FileSystemEvent> Function(String path)? watchStreamFactory,
  })  : _onSyncRequested = onSyncRequested,
        _debounceDuration = debounceDuration,
        _postSyncCooldown = postSyncCooldown,
        _watchStreamFactory = watchStreamFactory;

  final SyncRunCallback _onSyncRequested;
  final Duration _debounceDuration;
  final Duration _postSyncCooldown;
  final Stream<FileSystemEvent> Function(String path)? _watchStreamFactory;

  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _debounceTimer;
  bool _isSyncing = false;
  bool _pendingRun = false;
  DateTime? _suppressEventsUntil;
  String? _currentPath;
  String? _localDeviceId;
  bool _enabled = false;

  bool get isWatching => _subscription != null;

  void configure({
    required String? syncFolderPath,
    required bool enabled,
    required String localDeviceId,
  }) {
    final normalizedPath = syncFolderPath?.trim();
    final hasPath = normalizedPath != null && normalizedPath.isNotEmpty;
    final hasDeviceId = localDeviceId.trim().isNotEmpty;
    if (!enabled || !hasPath || !hasDeviceId) {
      stop();
      _enabled = enabled;
      _localDeviceId = localDeviceId;
      return;
    }

    final samePath = _currentPath == normalizedPath;
    final sameDevice = _localDeviceId == localDeviceId;
    final alreadyWatching = _subscription != null;
    if (alreadyWatching && samePath && sameDevice && _enabled == enabled) {
      return;
    }

    stop();
    _enabled = enabled;
    _localDeviceId = localDeviceId;
    _currentPath = normalizedPath;

    final watchStream = _watchStreamFactory?.call(normalizedPath) ??
        Directory(normalizedPath).watch(recursive: false);
    _subscription = watchStream.listen(
      _handleFileEvent,
      onError: (_) {
        // Keep app resilient to filesystem watcher errors; user can still sync manually.
      },
    );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _suppressEventsUntil = null;
    _currentPath = null;
  }

  Future<void> dispose() async {
    stop();
  }

  void _handleFileEvent(FileSystemEvent event) {
    if (!_enabled) return;
    final suppressUntil = _suppressEventsUntil;
    if (suppressUntil != null && DateTime.now().isBefore(suppressUntil)) {
      return;
    }
    final basename = p.basename(event.path);
    if (!_isDeviceFileName(basename)) return;
    if (_localDeviceId != null && _isDeviceFileFor(basename, _localDeviceId!)) {
      return;
    }
    _scheduleSync();
  }

  bool _isDeviceFileName(String name) {
    return name.startsWith('device_') && name.endsWith('.json');
  }

  bool _isDeviceFileFor(String name, String deviceId) {
    if (deviceId.trim().isEmpty || !_isDeviceFileName(name)) return false;
    final core = name.substring('device_'.length, name.length - '.json'.length);
    return core == deviceId || core.startsWith('$deviceId-');
  }

  void _scheduleSync() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () {
      unawaited(_runSyncSingleFlight());
    });
  }

  Future<void> _runSyncSingleFlight() async {
    if (_isSyncing) {
      _pendingRun = true;
      return;
    }

    _isSyncing = true;
    do {
      _pendingRun = false;
      try {
        await _onSyncRequested();
      } catch (_) {
        // Errors are already surfaced by caller-owned sync status.
      }
    } while (_pendingRun);
    _isSyncing = false;
    _beginPostSyncCooldown();
  }

  void _beginPostSyncCooldown() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _suppressEventsUntil = DateTime.now().add(_postSyncCooldown);
  }
}
