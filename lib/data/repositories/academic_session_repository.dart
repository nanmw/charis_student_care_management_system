import 'package:drift/drift.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Academic session repository: manages session options and current session.
/// Session options come from distinct values in tests table plus year-based defaults.
/// Current session is persisted in app_settings table.
class AcademicSessionRepository {
  AcademicSessionRepository(this._db);

  final AppDatabase _db;
  static const String _currentSessionKey = 'current_academic_session';

  /// Returns distinct academic session values from tests plus default options (current/adjacent years).
  /// Same logic as TestRepository.getAcademicSessionOptions() but moved here for global use.
  Future<List<String>> getSessionOptions() async {
    final allTests = await (_db.select(_db.tests)).get();
    final fromDb = <String>{};
    for (final t in allTests) {
      if (t.academicSession != null && t.academicSession!.trim().isNotEmpty) {
        fromDb.add(t.academicSession!.trim());
      }
    }
    final now = DateTime.now();
    final year = now.year;
    final currentSession = now.month >= 7 ? '$year-${year + 1}' : '${year - 1}-$year';
    final defaultSessions = [
      currentSession,
      '$year-${year + 1}',
      '${year - 1}-$year',
    ];
    final combined = <String>{...fromDb, ...defaultSessions};
    final list = combined.toList()..sort((a, b) => b.compareTo(a));
    return list;
  }

  /// Gets the current academic session from app_settings.
  /// Returns null if not set.
  Future<String?> getCurrentSession() async {
    final row = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(_currentSessionKey)))
        .getSingleOrNull();
    return row?.value;
  }

  /// Sets the current academic session in app_settings.
  /// If [value] is null, deletes the row (no current session).
  Future<void> setCurrentSession(String? value) async {
    if (value == null) {
      await (_db.delete(_db.appSettings)
            ..where((s) => s.key.equals(_currentSessionKey)))
          .go();
    } else {
      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: _currentSessionKey,
              value: Value(value),
            ),
          );
    }
  }

  /// Stream of the current academic session (reactive).
  /// Returns null if not set.
  Stream<String?> watchCurrentSession() {
    return (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(_currentSessionKey)))
        .watch()
        .map((rows) => rows.isEmpty ? null : rows.first.value);
  }
}
