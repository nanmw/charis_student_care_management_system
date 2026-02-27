import 'package:drift/drift.dart';

import 'users.dart';

/// Classes table: academic year levels (e.g. Year 1, Year 2, Year 3).
/// Supports facilitator attachment and promotions via class_id on students.
@DataClassName('SchoolClass')
class Classes extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Display name (e.g. "Year 1", "Year 2", "Year 3")
  TextColumn get name => text()();

  /// Sort order for display (1, 2, 3)
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// Optional facilitator (references users.id)
  IntColumn get facilitatorUserId =>
      integer().nullable().references(Users, #id)();

  /// When the record was created
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// When the record was last updated
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {name},
      ];
}
