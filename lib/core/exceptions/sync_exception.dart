/// Exception thrown during sync operations
class SyncException implements Exception {
  SyncException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'SyncException: $message${cause != null ? ' (Cause: $cause)' : ''}';
}
