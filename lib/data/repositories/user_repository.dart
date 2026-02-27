import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Repository for local users: auth (find by username, verify password) and CRUD for user management.
class UserRepository {
  UserRepository(this._db);

  final AppDatabase _db;

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
  Future<int> createUser({
    required String username,
    required String plainPassword,
    String? displayName,
    required UserRole role,
  }) async {
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
      createdAt: now,
      updatedAt: now,
    );
    return await _db.into(_db.users).insert(companion);
  }

  /// Updates user profile (display name, role, is_active). Optionally updates password if [newPlainPassword] is non-null.
  /// When [isActive] is set to false, or [role] is set to non-facilitator, clears this user from any class's facilitator assignment.
  Future<void> updateUser({
    required int id,
    String? displayName,
    UserRole? role,
    bool? isActive,
    String? newPlainPassword,
  }) async {
    if (isActive == false ||
        (role != null && role != UserRole.facilitator)) {
      await (_db.update(_db.classes)
            ..where((c) => c.facilitatorUserId.equals(id)))
          .write(const ClassesCompanion(facilitatorUserId: Value(null)));
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final companion = UsersCompanion(
      updatedAt: Value(now),
      displayName: displayName != null ? Value(displayName) : const Value.absent(),
      role: role != null ? Value(role.value) : const Value.absent(),
      isActive: isActive != null ? Value(isActive) : const Value.absent(),
      passwordHash: newPlainPassword != null && newPlainPassword.isNotEmpty
          ? Value(hashPassword(newPlainPassword))
          : const Value.absent(),
    );
    await (_db.update(_db.users)..where((t) => t.id.equals(id))).write(companion);
  }

  /// Sets user active flag (soft disable).
  Future<void> setActive(int id, bool active) async {
    await updateUser(id: id, isActive: active);
  }

  /// Gets user by id.
  Future<User?> getById(int id) async {
    return await (_db.select(_db.users)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
  }
}

class UserRepositoryException implements Exception {
  UserRepositoryException(this.message);
  final String message;
  @override
  String toString() => 'UserRepositoryException: $message';
}
