/// Exception thrown during authentication operations
class AuthException implements Exception {
  AuthException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() =>
      'AuthException: $message${cause != null ? ' (Cause: $cause)' : ''}';
}
