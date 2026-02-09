import 'package:drift/drift.dart';

/// App settings table: key-value storage for app-wide settings.
/// Used for storing the current academic session and other global preferences.
class AppSettings extends Table {
  /// Setting key (e.g. 'current_academic_session')
  TextColumn get key => text()();

  /// Setting value (e.g. '2024-2025')
  TextColumn get value => text().nullable()();

  @override
  Set<Column> get primaryKey => {key};
}
