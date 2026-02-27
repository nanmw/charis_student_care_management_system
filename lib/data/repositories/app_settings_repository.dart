import 'package:drift/drift.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Generic key-value repository for app_settings table.
/// Used for OneDrive URL and other global preferences.
class AppSettingsRepository {
  AppSettingsRepository(this._db);

  final AppDatabase _db;

  /// Key for the OneDrive connection URL (share link or API base URL).
  static const String keyOnedriveUrl = 'onedrive_url';

  /// Key for showing the Ministry Hours column on the dashboard summary table.
  /// Value 'true' = show, anything else or unset = hide.
  static const String keyDashboardShowMinistryHours =
      'dashboard_show_ministry_hours';

  /// Gets a setting value by key. Returns null if not set.
  Future<String?> get(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  /// Sets a setting value. If [value] is null, deletes the row.
  Future<void> set(String key, String? value) async {
    if (value == null) {
      await (_db.delete(_db.appSettings)..where((s) => s.key.equals(key))).go();
    } else {
      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: key,
              value: Value(value),
            ),
          );
    }
  }

  /// Stream of a setting value (reactive). Returns null if not set.
  Stream<String?> watch(String key) {
    return (_db.select(_db.appSettings)..where((s) => s.key.equals(key)))
        .watch()
        .map((rows) => rows.isEmpty ? null : rows.first.value);
  }
}
