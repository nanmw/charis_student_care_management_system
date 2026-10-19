import 'dart:async';

/// Whether [error] looks like a brief file lock / sharing violation (retryable).
bool isTransientIoError(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('errno = 32') ||
      text.contains('being used by another process') ||
      text.contains('cannot access the file because it is being used') ||
      text.contains('resource busy') ||
      text.contains('file is locked') ||
      text.contains('sharing violation') ||
      text.contains('text file busy') ||
      text.contains('pathaccessexception') ||
      // Generic FS access without permanent path-not-found.
      (text.contains('filesystemexception') &&
          !text.contains('no such file') &&
          !text.contains('pathnotfound') &&
          !text.contains('cannot find the path') &&
          !text.contains('errno = 2'));
}

/// Short user-facing message for sync failures.
String userFacingSyncError(Object error) {
  final text = error.toString().toLowerCase();

  if (text.contains('connection string is not set') ||
      text.contains('not configured')) {
    return 'Sync database is not configured. Add the Neon connection string in Settings → Sync.';
  }

  if (error is TimeoutException ||
      text.contains('timed out') ||
      text.contains('timeout')) {
    return 'Sync timed out. Check the internet connection and try again.';
  }

  if (text.contains('password') ||
      text.contains('authentication') ||
      text.contains('28p01')) {
    return 'The sync database rejected the connection string. Check it in Settings → Sync.';
  }

  if (isTransientIoError(error)) {
    return 'Couldn’t write to the sync folder (file busy). '
        'The app will retry shortly.';
  }

  if (text.contains('pathnotfound') ||
      text.contains('no such file') ||
      text.contains('cannot find the path') ||
      text.contains('errno = 2')) {
    return 'Sync folder not found. Check the path in Settings → Sync.';
  }

  if (text.contains('socket') ||
      text.contains('connection') ||
      text.contains('network') ||
      text.contains('failed host lookup') ||
      text.contains('postgres')) {
    return 'Couldn’t reach the sync database. Check the connection string in Settings → Sync and that you are online.';
  }

  if (text.contains('permission') ||
      text.contains('access is denied') ||
      text.contains('errno = 5') ||
      text.contains('operation not permitted') ||
      text.contains('errno = 13')) {
    return 'Couldn’t access the sync database. Check the connection string in Settings → Sync.';
  }

  return 'Sync failed. Check the connection string in Settings → Sync and try again.';
}

/// Retries [fn] when [isTransientIoError] matches, with short backoff.
Future<T> retryOnTransientIo<T>(
  Future<T> Function() fn, {
  int maxAttempts = 5,
  Duration Function(int attempt)? delayForAttempt,
}) async {
  var attempt = 0;
  while (true) {
    try {
      return await fn();
    } catch (e) {
      attempt++;
      if (!isTransientIoError(e) || attempt >= maxAttempts) rethrow;
      final delay = delayForAttempt?.call(attempt) ??
          Duration(milliseconds: 200 * attempt);
      await Future<void>.delayed(delay);
    }
  }
}
