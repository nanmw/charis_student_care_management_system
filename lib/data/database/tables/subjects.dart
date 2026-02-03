import 'package:drift/drift.dart';

/// Subjects table: stores subjects organized by year (Year 1, Year 2, Year 3).
/// Full-time and hybrid students share the same subjects for each year.
class Subjects extends Table {
  /// Auto-incrementing primary key
  IntColumn get id => integer().autoIncrement()();

  /// Subject name (e.g. "A Sure Foundation")
  TextColumn get name => text()();

  /// Year level: 'Year 1', 'Year 2', or 'Year 3'
  TextColumn get year => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {name, year}, // Prevent duplicate subject names within the same year
      ];
}
