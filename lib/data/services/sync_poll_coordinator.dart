import 'dart:async';

typedef SyncRunCallback = Future<void> Function();

/// Polls the sync database while the app is open.
///
/// The first tick waits one [interval], so startup sync is not duplicated.
class SyncPollCoordinator {
  SyncPollCoordinator({
    required SyncRunCallback onSyncRequested,
    this.interval = const Duration(seconds: 60),
  }) : _onSyncRequested = onSyncRequested;

  final SyncRunCallback _onSyncRequested;
  final Duration interval;

  Timer? _timer;
  bool _running = false;
  bool _pending = false;
  bool _active = false;

  bool get isPolling => _timer != null;

  void configure({
    required String? connectionString,
    required bool enabled,
  }) {
    final hasConnection =
        connectionString != null && connectionString.trim().isNotEmpty;
    if (!enabled || !hasConnection) {
      stop();
      return;
    }
    if (_active && _timer != null) return;

    stop();
    _active = true;
    _timer = Timer.periodic(interval, (_) {
      unawaited(_run());
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _active = false;
    _pending = false;
  }

  void dispose() {
    stop();
  }

  Future<void> _run() async {
    if (!_active) return;
    if (_running) {
      _pending = true;
      return;
    }
    _running = true;
    try {
      do {
        _pending = false;
        try {
          await _onSyncRequested();
        } catch (_) {
          // Errors are already surfaced by caller-owned sync status.
        }
      } while (_pending && _active);
    } finally {
      _running = false;
    }
  }
}
