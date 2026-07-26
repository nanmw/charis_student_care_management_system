import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/app_settings_repository.dart';

/// DTO for an academic session row (id, code, start/end dates, active, display name).
class AcademicSessionRecord {
  const AcademicSessionRecord({
    required this.id,
    required this.code,
    this.startDate,
    this.endDate,
    required this.isActive,
    this.displayName,
  });

  final int id;
  final String code;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool isActive;
  final String? displayName;
}

/// Academic session repository: manages session options and current session.
/// Backed by the academic_sessions table (plus app_settings for the current selection).
/// Session = one calendar year Feb–Oct; code is single year e.g. "2026".
class AcademicSessionRepository {
  AcademicSessionRepository(this._db, {void Function()? onLocalChangeSetWritten})
      : _onLocalChangeSetWritten = onLocalChangeSetWritten;

  final AppDatabase _db;
  final void Function()? _onLocalChangeSetWritten;
  static const _uuid = Uuid();
  static const String _currentSessionKey =
      AppSettingsRepository.keyCurrentAcademicSession;

  Future<String> _effectiveChangeSetDeviceId(String? deviceId) async {
    final d = deviceId?.trim();
    if (d != null && d.isNotEmpty && d != 'legacy') return d;
    return SyncFolderConfig.getOrCreateDeviceId();
  }

  /// Converts Unix seconds to DateTime (UTC). Returns null if null.
  static DateTime? _dateTimeFromSeconds(int? seconds) {
    if (seconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  /// Converts DateTime to Unix seconds. Returns null if null.
  static int? _secondsFromDateTime(DateTime? date) {
    if (date == null) return null;
    return date.toUtc().millisecondsSinceEpoch ~/ 1000;
  }

  /// Maps a Drift [AcademicSession] row to [AcademicSessionRecord].
  AcademicSessionRecord _recordFromRow(AcademicSession row) {
    return AcademicSessionRecord(
      id: row.id,
      code: row.code,
      startDate: _dateTimeFromSeconds(row.startDate),
      endDate: _dateTimeFromSeconds(row.endDate),
      isActive: row.isActive,
      displayName: row.displayName,
    );
  }

  /// Stream of all academic sessions (for Settings list and dropdown). Ordered by code DESC.
  Stream<List<AcademicSessionRecord>> watchAllSessions() {
    return (_db.select(_db.academicSessions)
          ..orderBy([(t) => OrderingTerm.desc(t.code)]))
        .watch()
        .map((rows) => rows.map(_recordFromRow).toList());
  }

  /// Returns distinct academic session codes from academic_sessions only.
  /// If DB is empty, returns a list with [suggestedSessionCode] so dropdowns have a default.
  Future<List<String>> getSessionOptions() async {
    final fromDb = <String>[];
    try {
      final result = await _db.customSelect(
        'SELECT DISTINCT code FROM academic_sessions ORDER BY code DESC',
        readsFrom: {_db.academicSessions},
      ).get();
      for (final row in result) {
        final code = row.data['code'] as String?;
        if (code != null && code.trim().isNotEmpty) {
          fromDb.add(code.trim());
        }
      }
    } catch (_) {
      // Table may not exist yet (fresh install before migration).
    }
    if (fromDb.isEmpty) {
      final suggested = suggestedSessionCode();
      if (suggested != null) fromDb.add(suggested);
    }
    return fromDb;
  }

  /// Suggested session code for new sessions (e.g. current year as "2026").
  static String? suggestedSessionCode() {
    return DateTime.now().year.toString();
  }

  /// Suggested start date for a session (1 Feb of [code] year). [code] can be "2026" or legacy "2024-2025".
  static DateTime? suggestedStartDate(String code) {
    final year = int.tryParse(code.trim().split('-').first);
    if (year == null) return null;
    return DateTime.utc(year, 2, 1);
  }

  /// Suggested end date for a session (31 Oct of [code] year).
  static DateTime? suggestedEndDate(String code) {
    final year = int.tryParse(code.trim().split('-').first);
    if (year == null) return null;
    return DateTime.utc(year, 10, 31);
  }

  /// Inserts a new academic session. If [isActive] is true, marks all others inactive.
  Future<int> insertSession({
    required String code,
    required UserRole userRole,
    DateTime? startDate,
    DateTime? endDate,
    bool isActive = false,
    String? displayName,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageAcademicSession(userRole)) {
      throw StateError('Role cannot manage academic sessions');
    }
    final trimmedCode = code.trim();
    if (trimmedCode.isEmpty) throw ArgumentError('Session code cannot be empty');
    if (isActive) await _setOthersInactive(trimmedCode);
    final companion = AcademicSessionsCompanion.insert(
      code: trimmedCode,
      startDate: Value(_secondsFromDateTime(startDate)),
      endDate: Value(_secondsFromDateTime(endDate)),
      isActive: Value(isActive),
      displayName: Value(displayName?.trim()),
    );
    final id = await _db.into(_db.academicSessions).insert(companion);
    if (userId != null) {
      final row = await (_db.select(_db.academicSessions)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row != null) {
        await _insertChangeSet(
          table: 'academic_sessions',
          recordId: id.toString(),
          operation: 'INSERT',
          payload: _payloadFromSession(row),
          userId: userId,
          version: 1,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: screen,
        );
      }
    }
    return id;
  }

  /// Updates an existing academic session. If [isActive] is true, marks all others inactive.
  Future<void> updateSession(
    int id, {
    required UserRole userRole,
    String? code,
    DateTime? startDate,
    DateTime? endDate,
    bool? isActive,
    String? displayName,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageAcademicSession(userRole)) {
      throw StateError('Role cannot manage academic sessions');
    }
    final row = await (_db.select(_db.academicSessions)..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    final newCode = code?.trim() ?? row.code;
    if (newCode.isEmpty) throw ArgumentError('Session code cannot be empty');
    await (_db.update(_db.academicSessions)..where((t) => t.id.equals(id))).write(
      AcademicSessionsCompanion(
        code: code != null ? Value(code.trim()) : const Value.absent(),
        startDate: startDate != null ? Value(_secondsFromDateTime(startDate)) : const Value.absent(),
        endDate: endDate != null ? Value(_secondsFromDateTime(endDate)) : const Value.absent(),
        isActive: isActive != null ? Value(isActive) : const Value.absent(),
        displayName: displayName != null ? Value(displayName.trim()) : const Value.absent(),
      ),
    );
    if (isActive == true) await _setOthersInactive(newCode);
    if (userId != null) {
      final updated = await (_db.select(_db.academicSessions)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (updated != null) {
        await _insertChangeSet(
          table: 'academic_sessions',
          recordId: id.toString(),
          operation: 'UPDATE',
          payload: _payloadFromSession(updated),
          userId: userId,
          version: 1,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: screen,
        );
      }
    }
  }

  Future<void> _setOthersInactive(String activeCode) async {
    await _db.customStatement(
      'UPDATE academic_sessions SET is_active = 0 WHERE code <> ?',
      [activeCode],
    );
    await _db.customStatement(
      'UPDATE academic_sessions SET is_active = 1 WHERE code = ?',
      [activeCode],
    );
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
  Future<void> setCurrentSession(
    String? value, {
    required UserRole userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (!RolePermissions.canManageAcademicSession(userRole)) {
      throw StateError('Role cannot manage academic sessions');
    }
    final nowIso = DateTime.now().toUtc().toIso8601String();
    if (value == null) {
      await (_db.delete(_db.appSettings)
            ..where((s) => s.key.equals(_currentSessionKey)))
          .go();
    } else {
      final trimmed = value.trim();
      try {
        await _db.customStatement(
          '''
          INSERT OR IGNORE INTO academic_sessions (code, is_active)
          VALUES (?, 0)
          ''',
          [trimmed],
        );
        await _setOthersInactive(trimmed);
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
    if (userId != null) {
      await _insertChangeSet(
        table: 'app_settings',
        recordId: _currentSessionKey,
        operation: value == null ? 'DELETE' : 'UPDATE',
        payload: {
          'key': _currentSessionKey,
          if (value != null) 'value': value.trim(),
          'updatedAt': nowIso,
        },
        userId: userId,
        version: 1,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: screen,
      );
    }
  }

  /// Stream of the current academic session (reactive).
  Stream<String?> watchCurrentSession() {
    return (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(_currentSessionKey)))
        .watch()
        .map((rows) => rows.isEmpty ? null : rows.first.value);
  }

  /// Resolves academic_session_id by session code (e.g. "2026" or legacy "2024-2025").
  Future<int?> getSessionIdByCode(String code) async {
    if (code.trim().isEmpty) return null;
    try {
      final result = await _db.customSelect(
        'SELECT id FROM academic_sessions WHERE code = ? LIMIT 1',
        variables: [Variable.withString(code.trim())],
        readsFrom: {_db.academicSessions},
      ).getSingleOrNull();
      return result?.data['id'] as int?;
    } catch (_) {
      return null;
    }
  }

  /// Derives the year from a session code. Single-year "2026" -> "2026"; legacy "2024-2025" -> "2024".
  /// Used for legacy [payments].year and display.
  static String? yearFromSessionCode(String? sessionCode) {
    if (sessionCode == null || sessionCode.trim().isEmpty) return null;
    final parts = sessionCode.trim().split('-');
    if (parts.isEmpty) return null;
    final y = int.tryParse(parts.first);
    return y?.toString();
  }

  Map<String, dynamic> _payloadFromSession(AcademicSession row) {
    return {
      'code': row.code,
      if (row.startDate != null) 'startDate': row.startDate,
      if (row.endDate != null) 'endDate': row.endDate,
      'isActive': row.isActive,
      if (row.displayName != null) 'displayName': row.displayName,
    };
  }

  Future<void> _insertChangeSet({
    required String table,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    required String userId,
    required int version,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    final effectiveDeviceId = await _effectiveChangeSetDeviceId(deviceId);
    final fullPayload = Map<String, dynamic>.from(payload);
    if (userDisplayName != null) fullPayload['userDisplayName'] = userDisplayName;
    if (screen != null) fullPayload['screen'] = screen;
    await _db.into(_db.changeSets).insert(
          ChangeSetsCompanion.insert(
            id: _uuid.v4(),
            table: table,
            recordId: recordId,
            operation: operation,
            payload: jsonEncode(fullPayload),
            userId: userId,
            version: version,
            deviceId: effectiveDeviceId,
          ),
        );
    _onLocalChangeSetWritten?.call();
  }
}
