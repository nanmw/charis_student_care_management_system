import 'package:drift/drift.dart';

/// Local users table for username/password authentication and role-based access.
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get username => text()();
  TextColumn get passwordHash => text()();
  TextColumn get displayName => text().nullable()();
  /// Role: 'facilitator' | 'adminLevel02' | 'adminLevel01'
  TextColumn get role => text()();
  /// For facilitators: the single class (year level) they can access. Null for admin/portfolio lead.
  IntColumn get allowedClassId => integer().nullable()();
  /// For facilitators: the single mode (e.g. 'Full-time', 'Hybrid') they can access. Null for admin/portfolio lead.
  TextColumn get allowedMode => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();
}
