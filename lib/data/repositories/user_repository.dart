import 'dart:async';
import 'dart:convert';

import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Retries [fn] up to [maxAttempts] times when SQLite returns "database is locked" (code 5).
/// Useful when the DB file is briefly locked by another process (e.g. sync/backup).
Future<T> _retryOnLocked<T>(Future<T> Function() fn, {int maxAttempts = 3}) async {
  var attempt = 0;
  while (true) {
    try {
      return await fn();
    } catch (e, _) {
      final msg = e.toString();
      final isLocked = msg.contains('code 5') || msg.contains('database is locked');
      attempt++;
      if (!isLocked || attempt >= maxAttempts) rethrow;
    }
    await Future<void>.delayed(Duration(milliseconds: 100 * attempt));
  }
}

/// Repository for local users: auth (find by username, verify password) and CRUD for user management.
class UserRepository {
  UserRepository(this._db, {void Function()? onLocalChangeSetWritten})
      : _onLocalChangeSetWritten = onLocalChangeSetWritten;

  final AppDatabase _db;
  final void Function()? _onLocalChangeSetWritten;
  static const _uuid = Uuid();

  Future<String> _effectiveChangeSetDeviceId(String? deviceId) async {
    final d = deviceId?.trim();
    if (d != null && d.isNotEmpty && d != 'legacy') return d;
    return SyncFolderConfig.getOrCreateDeviceId();
  }

  /// Finds a user by username (case-sensitive). Returns null if not found.
  Future<User?> findByUsername(String username) async {
    final row = await (_db.select(_db.users)
          ..where((t) => t.username.equals(username)))
        .getSingleOrNull();
    return row;
  }

  /// Verifies [plainPassword] against [passwordHash]. Returns true if match.
  bool verifyPassword(String plainPassword, String passwordHash) {
    return BCrypt.checkpw(plainPassword, passwordHash);
  }

  /// Hashes [plainPassword] with bcrypt for storage.
  static String hashPassword(String plainPassword) {
    return BCrypt.hashpw(plainPassword, BCrypt.gensalt());
  }

  /// Returns the user if credentials are valid and user is active; otherwise null.
  Future<User?> validateCredentials(String username, String password) async {
    final user = await findByUsername(username);
    if (user == null || !user.isActive) return null;
    if (!verifyPassword(password, user.passwordHash)) return null;
    return user;
  }

  /// Lists all users (for admin user management).
  Future<List<User>> listUsers() async {
    return await (_db.select(_db.users)
          ..orderBy([(t) => OrderingTerm.asc(t.username)]))
        .get();
  }

  /// Stream of all users for reactive UI.
  Stream<List<User>> watchUsers() {
    return (_db.select(_db.users)
          ..orderBy([(t) => OrderingTerm.asc(t.username)]))
        .watch();
  }

  /// Creates a new user. Throws if username already exists.
  /// For facilitators, [allowedClassId] and [allowedMode] define scope (one class + one mode).
  /// Pass [userId]/[deviceId] to emit a sync change-set (omit for seed).
  Future<int> createUser({
    required String username,
    required String plainPassword,
    String? displayName,
    required UserRole role,
    int? allowedClassId,
    String? allowedMode,
    required UserRole actorRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageUsers(actorRole)) {
      throw StateError('Role cannot manage users');
    }
    final existing = await findByUsername(username);
    if (existing != null) {
      throw UserRepositoryException('Username already exists');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final companion = UsersCompanion.insert(
      username: username,
      passwordHash: hashPassword(plainPassword),
      displayName: Value(displayName),
      role: role.value,
      allowedClassId: Value(role == UserRole.facilitator ? allowedClassId : null),
      allowedMode: Value(role == UserRole.facilitator && allowedMode != null && allowedMode.isNotEmpty ? allowedMode : null),
      createdAt: now,
      updatedAt: now,
    );
    final id = await _db.into(_db.users).insert(companion);
    if (userId != null) {
      final row = await getById(id);
      if (row != null) {
        await _insertChangeSet(
          table: 'users',
          recordId: id.toString(),
          operation: 'INSERT',
          payload: await _payloadFromUser(row),
          userId: userId,
          version: 1,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: screen,
        );
      }
    }
    return id;
  }

  /// Updates user profile (display name, role, is_active, allowed_class_id, allowed_mode). Optionally updates password if [newPlainPassword] is non-null.
  /// When [isActive] is set to false, or [role] is set to non-facilitator, clears this user from any class's facilitator assignment and clears allowed_class_id/allowed_mode.
  Future<void> updateUser({
    required int id,
    String? displayName,
    UserRole? role,
    bool? isActive,
    String? newPlainPassword,
    int? allowedClassId,
    String? allowedMode,
    required UserRole actorRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageUsers(actorRole)) {
      throw StateError('Role cannot manage users');
    }
    if (isActive == false ||
        (role != null && role != UserRole.facilitator)) {
      await _retryOnLocked(() async {
        await (_db.update(_db.classes)
              ..where((c) => c.facilitatorUserId.equals(id)))
            .write(const ClassesCompanion(facilitatorUserId: Value(null)));
      });
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final bool clearScope = role != null && role != UserRole.facilitator;
    final companion = UsersCompanion(
      updatedAt: Value(now),
      displayName: displayName != null ? Value(displayName) : const Value.absent(),
      role: role != null ? Value(role.value) : const Value.absent(),
      isActive: isActive != null ? Value(isActive) : const Value.absent(),
      allowedClassId: clearScope
          ? const Value(null)
          : (allowedClassId != null ? Value(allowedClassId) : const Value.absent()),
      allowedMode: clearScope
          ? const Value(null)
          : (allowedMode != null && allowedMode.isNotEmpty ? Value(allowedMode) : const Value.absent()),
      passwordHash: newPlainPassword != null && newPlainPassword.isNotEmpty
          ? Value(hashPassword(newPlainPassword))
          : const Value.absent(),
    );
    await (_db.update(_db.users)..where((t) => t.id.equals(id))).write(companion);
    if (userId != null) {
      final row = await getById(id);
      if (row != null) {
        await _insertChangeSet(
          table: 'users',
          recordId: id.toString(),
          operation: 'UPDATE',
          payload: await _payloadFromUser(row),
          userId: userId,
          version: 1,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: screen,
        );
      }
    }
  }

  /// Sets user active flag (soft disable).
  Future<void> setActive(
    int id,
    bool active, {
    required UserRole actorRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    await updateUser(
      id: id,
      isActive: active,
      actorRole: actorRole,
      userId: userId,
      deviceId: deviceId,
      userDisplayName: userDisplayName,
      screen: screen,
    );
  }

  /// Permanently deletes a user. Clears any class facilitator assignment first to satisfy FK.
  /// Throws [UserRepositoryException] if deleting the last administrator.
  Future<void> deleteUser(
    int id, {
    required UserRole actorRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageUsers(actorRole)) {
      throw StateError('Role cannot manage users');
    }
    final user = await getById(id);
    if (user != null && user.role == UserRole.adminLevel01.value) {
      final admins = await (_db.select(_db.users)
            ..where((t) => t.role.equals(UserRole.adminLevel01.value)))
          .get();
      if (admins.length <= 1) {
        throw UserRepositoryException('Cannot delete the last administrator');
      }
    }
    final payload = user != null ? await _payloadFromUser(user) : <String, dynamic>{};
    await _retryOnLocked(() async {
      await (_db.update(_db.classes)
            ..where((c) => c.facilitatorUserId.equals(id)))
          .write(const ClassesCompanion(facilitatorUserId: Value(null)));
      await (_db.delete(_db.users)..where((t) => t.id.equals(id))).go();
    });
    if (userId != null && user != null) {
      await _insertChangeSet(
        table: 'users',
        recordId: id.toString(),
        operation: 'DELETE',
        payload: payload,
        userId: userId,
        version: 1,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  /// Gets user by id.
  Future<User?> getById(int id) async {
    return await (_db.select(_db.users)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }

  /// Builds a sync payload from the current local user row (for keep-local heal).
  Future<Map<String, dynamic>> payloadFromUser(User row) => _payloadFromUser(row);

  Future<Map<String, dynamic>> _payloadFromUser(User row) async {
    String? allowedClassName;
    if (row.allowedClassId != null) {
      final c = await (_db.select(_db.classes)
            ..where((t) => t.id.equals(row.allowedClassId!)))
          .getSingleOrNull();
      allowedClassName = c?.name;
    }
    return {
      'username': row.username,
      'passwordHash': row.passwordHash,
      'displayName': row.displayName,
      'role': row.role,
      'isActive': row.isActive,
      if (allowedClassName != null) 'allowedClassName': allowedClassName,
      if (row.allowedMode != null && row.allowedMode!.isNotEmpty)
        'allowedMode': row.allowedMode,
      'updatedAt': row.updatedAt,
      'createdAt': row.createdAt,
    };
  }

  Future<void> _insertChangeSet({
    required String table,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    required String userId,
    required int version,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    final effectiveDeviceId = await _effectiveChangeSetDeviceId(deviceId);
    final fullPayload = Map<String, dynamic>.from(payload);
    if (userDisplayName != null) fullPayload['userDisplayName'] = userDisplayName;
    if (screen != null) fullPayload['screen'] = screen;
    await _db.into(_db.changeSets).insert(
          ChangeSetsCompanion.insert(
            id: _uuid.v4(),
            table: table,
            recordId: recordId,
            operation: operation,
            payload: jsonEncode(fullPayload),
            userId: userId,
            version: version,
            deviceId: effectiveDeviceId,
          ),
        );
    _onLocalChangeSetWritten?.call();
  }
}

class UserRepositoryException implements Exception {
  UserRepositoryException(this.message);
  final String message;
  @override
  String toString() => 'UserRepositoryException: $message';
}
