/// Auth configuration for Microsoft Entra ID (OAuth2).
/// Set via environment or config; do not commit secrets.
class AuthConfig {
  AuthConfig._();

  /// Azure AD / Entra ID application (client) ID
  static const String clientId = String.fromEnvironment(
    'CHARIS_AUTH_CLIENT_ID',
    defaultValue: '',
  );

  /// Azure AD tenant ID (or 'common' for multi-tenant)
  static const String tenantId = String.fromEnvironment(
    'CHARIS_AUTH_TENANT_ID',
    defaultValue: 'common',
  );

  /// When true, skip real Microsoft login and use a dev user (for local development).
  /// Run with: --dart-define=CHARIS_AUTH_SKIP=true
  static const bool skipAuth = bool.fromEnvironment(
    'CHARIS_AUTH_SKIP',
    defaultValue: false,
  );

  /// Redirect URI for desktop (local loopback)
  static const String redirectUri = 'http://localhost:8080/callback';

  /// Scopes: openid for id_token, profile for name, email for email
  static const List<String> scopes = ['openid', 'profile', 'email'];

  static Uri get authorizationEndpoint => Uri.parse(
        'https://login.microsoftonline.com/$tenantId/oauth2/v2.0/authorize',
      );

  static Uri get tokenEndpoint => Uri.parse(
        'https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token',
      );
}
