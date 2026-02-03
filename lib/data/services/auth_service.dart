import 'dart:convert';
import 'dart:io';

import 'package:charis_student_care/core/config/auth_config.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/exceptions/auth_exception.dart';
import 'package:charis_student_care/data/models/auth_user.dart';
import 'package:http/http.dart' as http;
import 'package:oauth2/oauth2.dart';
import 'package:url_launcher/url_launcher.dart';

/// Microsoft Entra ID (OAuth2) authentication service for desktop.
/// Uses authorization code flow with local redirect; role from config map for MVP.
class AuthService {
  AuthService({
    http.Client? httpClient,
    Map<String, UserRole>? roleByUserId,
  })  : _httpClient = httpClient ?? http.Client(),
        _roleByUserId = roleByUserId ?? _defaultRoleMap;

  static final Map<String, UserRole> _defaultRoleMap = {
    // Add user IDs from Entra ID (oid claim) to assign roles for MVP.
    // Example: '00000000-0000-0000-0000-000000000000': UserRole.adminLevel01,
  };

  final http.Client _httpClient;
  final Map<String, UserRole> _roleByUserId;

  Credentials? _credentials;
  AuthUser? _currentUser;

  static const AuthUser _devUser = AuthUser(
    id: 'dev-user',
    displayName: 'Dev User',
    email: 'dev@local',
  );

  /// Whether a session is restored (credentials + user).
  bool get isAuthenticated =>
      (AuthConfig.skipAuth && _currentUser != null) ||
      (_credentials != null && _currentUser != null);

  /// Current user; null if not authenticated.
  AuthUser? get user => _currentUser;

  /// Access token for API calls; null if not authenticated.
  String? get accessToken => _credentials?.accessToken;

  /// Initiates login: opens browser, listens for redirect, exchanges code for tokens, fetches user.
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

  /// Signs out: clears stored credentials and user.
  void logout() {
    _credentials = null;
    _currentUser = null;
  }

  /// Returns the role for the current user (from config map for MVP).
  UserRole getRole() {
    if (AuthConfig.skipAuth) return UserRole.adminLevel01;
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

  Future<String?> _listenForRedirectCode(Uri redirectUri, Uri authUrl) async {
    final port = redirectUri.port;
    final path = redirectUri.path;

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    try {
      launchUrl(authUrl, mode: LaunchMode.externalApplication);
      final request = await server.first;
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
