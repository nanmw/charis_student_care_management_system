import 'dart:convert';
import 'dart:io';

import 'package:charis_student_care/core/config/auth_config.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/exceptions/auth_exception.dart';
import 'package:charis_student_care/data/models/auth_user.dart';
import 'package:charis_student_care/data/repositories/user_repository.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart';
import 'package:url_launcher/url_launcher.dart';

/// Authentication: local username/password (users table) and optional Microsoft OAuth for OneDrive.
/// Role for local users comes from DB; for Microsoft users from config map.
class AuthService {
  AuthService({
    UserRepository? userRepository,
    http.Client? httpClient,
    Map<String, UserRole>? roleByUserId,
  })  : _userRepository = userRepository,
        _httpClient = httpClient ?? http.Client(),
        _roleByUserId = roleByUserId ?? _defaultRoleMap;

  static final Map<String, UserRole> _defaultRoleMap = {
    // Add user IDs from Entra ID (oid claim) to assign roles when using Microsoft login.
  };

  final UserRepository? _userRepository;
  final http.Client _httpClient;
  final Map<String, UserRole> _roleByUserId;

  Credentials? _credentials;
  AuthUser? _currentUser;
  /// Role for local (DB) user; null when user is from Microsoft OAuth.
  UserRole? _currentUserRole;

  static const AuthUser _devUser = AuthUser(
    id: 'dev-user',
    displayName: 'Dev User',
    email: 'dev@local',
  );

  /// Whether a session is restored (credentials + user) or local login (user + role).
  bool get isAuthenticated =>
      (AuthConfig.skipAuth && _currentUser != null) ||
      (_currentUser != null && (_currentUserRole != null || _credentials != null));

  /// Current user; null if not authenticated.
  AuthUser? get user => _currentUser;

  /// Access token for API calls; null if not authenticated.
  String? get accessToken => _credentials?.accessToken;

  /// Local login with username and password. Validates against users table.
  Future<void> loginWithCredentials(String username, String password) async {
    if (AuthConfig.skipAuth) {
      _currentUser = _devUser;
      _currentUserRole = UserRole.adminLevel01;
      return;
    }
    final repo = _userRepository;
    if (repo == null) {
      throw AuthException('User repository not available');
    }
    final user = await repo.validateCredentials(username, password);
    if (user == null) {
      throw AuthException('Invalid username or password');
    }
    _currentUser = AuthUser(
      id: user.id.toString(),
      displayName: user.displayName ?? user.username,
      email: null,
    );
    _currentUserRole = UserRole.fromString(user.role);
  }

  /// Microsoft OAuth: opens browser, listens for redirect, exchanges code for tokens.
  /// Used for OneDrive connection after local login, or standalone if desired.
  Future<void> login() async {
    if (AuthConfig.skipAuth) {
      _currentUser = _devUser;
      return;
    }
    if (AuthConfig.clientId.isEmpty) {
      throw AuthException(
        'Auth not configured: set CHARIS_AUTH_CLIENT_ID (e.g. via --dart-define)',
      );
    }

    final grant = AuthorizationCodeGrant(
      AuthConfig.clientId,
      AuthConfig.authorizationEndpoint,
      AuthConfig.tokenEndpoint,
      secret: null,
      httpClient: _httpClient,
    );

    final redirectUri = Uri.parse(AuthConfig.redirectUri);
    final state = _randomState();
    final authUrl = grant.getAuthorizationUrl(
      redirectUri,
      scopes: [...AuthConfig.scopes, 'User.Read'],
      state: state,
    );

    final code = await _listenForRedirectCode(redirectUri, authUrl);
    if (code == null || code.isEmpty) {
      throw AuthException('No authorization code received');
    }

    try {
      final client = await grant.handleAuthorizationResponse({
        'code': code,
        'state': state,
      });
      _credentials = client.credentials;

      final user = await _fetchUserFromGraph(client);
      if (user == null) {
        throw AuthException('Could not load user profile');
      }
      _currentUser = user;
    } on AuthorizationException catch (e) {
      throw AuthException(e.toString(), e);
    }
  }

  /// OneDrive connection: runs Microsoft OAuth with OneDrive scopes and stores credentials.
  /// Does not change _currentUser (used after local login). Throws if not configured or user cancels.
  Future<void> connectOneDrive() async {
    if (AuthConfig.skipAuth) return;
    if (AuthConfig.clientId.isEmpty) return;

    final grant = AuthorizationCodeGrant(
      AuthConfig.clientId,
      AuthConfig.authorizationEndpoint,
      AuthConfig.tokenEndpoint,
      secret: null,
      httpClient: _httpClient,
    );

    final redirectUri = Uri.parse(AuthConfig.redirectUri);
    final state = _randomState();
    final authUrl = grant.getAuthorizationUrl(
      redirectUri,
      scopes: [...AuthConfig.scopes, 'User.Read', 'Files.ReadWrite'],
      state: state,
    );

    final code = await _listenForRedirectCode(redirectUri, authUrl);
    if (code == null || code.isEmpty) {
      throw AuthException('OneDrive connection cancelled or failed');
    }

    final client = await grant.handleAuthorizationResponse({
      'code': code,
      'state': state,
    });
    _credentials = client.credentials;
  }

  /// Signs out: clears stored credentials and user.
  void logout() {
    _credentials = null;
    _currentUser = null;
    _currentUserRole = null;
  }

  /// Returns the role for the current user (from DB for local user, config map for Microsoft).
  UserRole getRole() {
    if (AuthConfig.skipAuth) return UserRole.adminLevel01;
    if (_currentUserRole != null) return _currentUserRole!;
    final u = _currentUser;
    if (u == null) return UserRole.facilitator;
    return _roleByUserId[u.id] ?? UserRole.facilitator;
  }

  /// Restores session from stored credentials if available (e.g. secure storage).
  /// This implementation does not persist across restarts; override or extend for persistence.
  Future<void> restoreSession() async {
    if (AuthConfig.skipAuth) {
      _currentUser = _devUser;
      return;
    }
    // No-op for in-memory MVP; can be extended with secure storage.
  }

  static String _randomState() {
    final values = List<int>.generate(16, (i) => DateTime.now().millisecondsSinceEpoch % 256);
    return base64Url.encode(values);
  }

  /// Timeout for waiting on OAuth redirect (e.g. OneDrive or Microsoft sign-in).
  static const Duration _oauthRedirectTimeout = Duration(seconds: 30);

  Future<String?> _listenForRedirectCode(Uri redirectUri, Uri authUrl) async {
    final port = redirectUri.port;
    final path = redirectUri.path;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    try {
      launchUrl(authUrl, mode: LaunchMode.externalApplication);
      final request = await server.first.timeout(
        _oauthRedirectTimeout,
        onTimeout: () => throw AuthException(
          'Connection timed out. You can try again later from settings.',
        ),
      );
      final uri = request.uri;
      if (uri.path != path) {
        await _respondHtml(request, 400, 'Bad path');
        return null;
      }
      final code = uri.queryParameters['code'];
      await _respondHtml(
        request,
        200,
        'You can close this window and return to the app.',
      );
      return code;
    } finally {
      await server.close(force: true);
    }
  }

  Future<void> _respondHtml(HttpRequest request, int status, String body) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.html
      ..write('<!DOCTYPE html><html><body><p>$body</p></body></html>');
    await request.response.close();
  }

  Future<AuthUser?> _fetchUserFromGraph(Client client) async {
    final response = await client.get(
      Uri.parse('https://graph.microsoft.com/v1.0/me'),
    );
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final id = json['id'] as String?;
    if (id == null) return null;
    final displayName = json['displayName'] as String? ?? json['userPrincipalName'] as String? ?? id;
    final email = json['mail'] as String? ?? json['userPrincipalName'] as String?;
    return AuthUser(id: id, displayName: displayName, email: email);
  }
}
