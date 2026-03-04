import 'package:drift/drift.dart';
import 'package:charis_student_care/data/database/app_database.dart';

/// Academic session repository: manages session options and current session.
/// Backed by the academic_sessions table (via raw SQL) plus app_settings for the current selection.
class AcademicSessionRepository {
  AcademicSessionRepository(this._db);

  final AppDatabase _db;
  static const String _currentSessionKey = 'current_academic_session';

  /// Returns distinct academic session codes from academic_sessions plus default options.
  /// Kept for compatibility with existing dropdowns that expect List<String>.
  Future<List<String>> getSessionOptions() async {
    // Read distinct codes from academic_sessions via raw SQL to avoid depending
    // on generated Drift accessors before codegen has run.
    final fromDb = <String>{};
    try {
      final result = await _db.customSelect(
        'SELECT DISTINCT code FROM academic_sessions ORDER BY code DESC',
        readsFrom: const {},
      ).get();
      for (final row in result) {
        final code = row.data['code'] as String?;
        if (code != null && code.trim().isNotEmpty) {
          fromDb.add(code.trim());
        }
      }
    } catch (_) {
      // Table may not exist yet (fresh install before migration); fall back
      // to defaults only.
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

  /// Gets the current academic session code from app_settings.
  /// Returns null if not set.
  Future<String?> getCurrentSession() async {
    final row = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(_currentSessionKey)))
        .getSingleOrNull();
    return row?.value;
  }

  /// Sets the current academic session code in app_settings and updates academic_sessions.is_active flags.
  /// If [value] is null, deletes the row (no current session).
  Future<void> setCurrentSession(String? value) async {
    if (value == null) {
      await (_db.delete(_db.appSettings)
            ..where((s) => s.key.equals(_currentSessionKey)))
          .go();
    } else {
      final trimmed = value.trim();
      // Update academic_sessions via raw SQL so this compiles even before Drift
      // has generated accessors for the new table.
      try {
        // Ensure the row exists.
        await _db.customStatement(
          '''
          INSERT OR IGNORE INTO academic_sessions (code, is_active)
          VALUES (?, 0)
          ''',
          [trimmed],
        );
        // Mark this session active and all others inactive.
        await _db.customStatement(
          'UPDATE academic_sessions SET is_active = 1 WHERE code = ?',
          [trimmed],
        );
        await _db.customStatement(
          'UPDATE academic_sessions SET is_active = 0 WHERE code <> ?',
          [trimmed],
        );
      } catch (_) {
        // If the table doesn't exist yet, we still persist the value in app_settings.
      }

      await _db.into(_db.appSettings).insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: _currentSessionKey,
              value: Value(trimmed),
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

  /// Resolves academic_session_id by session code (e.g. "2024-2025").
  /// Returns null if the code is not found or table is unavailable.
  Future<int?> getSessionIdByCode(String code) async {
    if (code.trim().isEmpty) return null;
    try {
      final result = await _db.customSelect(
        'SELECT id FROM academic_sessions WHERE code = ? LIMIT 1',
        variables: [Variable.withString(code.trim())],
        readsFrom: const {},
      ).getSingleOrNull();
      return result?.data['id'] as int?;
    } catch (_) {
      return null;
    }
  }

  /// Derives the start year from a session code (e.g. "2024-2025" -> 2024).
  /// Used for legacy [payments].year and display.
  static String? yearFromSessionCode(String? sessionCode) {
    if (sessionCode == null || sessionCode.trim().isEmpty) return null;
    final parts = sessionCode.trim().split('-');
    if (parts.isEmpty) return null;
    final y = int.tryParse(parts.first);
    return y?.toString();
  }
}
