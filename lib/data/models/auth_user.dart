/// Minimal authenticated user model (from Entra ID / OAuth2).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.displayName,
    this.email,
  });

  final String id;
  final String displayName;
  final String? email;
}
