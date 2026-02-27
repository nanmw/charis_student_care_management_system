import 'package:drift/drift.dart';

import 'classes.dart';

/// Subjects table: stores subjects organized by class (Year 1, Year 2, Year 3).
/// Full-time and hybrid students share the same subjects for each class.
class Subjects extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Subject name (e.g. "A Sure Foundation")
  TextColumn get name => text()();

  /// Class (year level) – references classes.id
  IntColumn get classId => integer().references(Classes, #id)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {name, classId}, // Prevent duplicate subject names within the same class
      ];
}
