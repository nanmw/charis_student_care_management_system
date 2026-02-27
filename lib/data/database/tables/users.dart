import 'package:drift/drift.dart';

/// Local users table for username/password authentication and role-based access.
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text()();
  TextColumn get passwordHash => text()();
  TextColumn get displayName => text().nullable()();
  /// Role: 'facilitator' | 'adminLevel02' | 'adminLevel01'
  TextColumn get role => text()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}
