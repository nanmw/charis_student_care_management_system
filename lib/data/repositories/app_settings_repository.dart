import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/domain/attendance/attendance_thresholds.dart';

/// Generic key-value repository for app_settings table.
/// Used for OneDrive URL and other global preferences.
class AppSettingsRepository {
  AppSettingsRepository(this._db, {void Function()? onLocalChangeSetWritten})
      : _onLocalChangeSetWritten = onLocalChangeSetWritten;

  final AppDatabase _db;
  final void Function()? _onLocalChangeSetWritten;
  static const _uuid = Uuid();

  /// Key for the OneDrive connection URL (share link or API base URL).
  static const String keyOnedriveUrl = 'onedrive_url';
  static const String keyMonthlyTuitionFee = 'monthly_tuition_fee';
  static const String keyLumpSumDiscountPercent = 'lump_sum_discount_percent';
  static const String keyAttendanceExpectedDaysMonth =
      'attendance_expected_days_month';
  static const String keyAttendanceExpectedDaysTerm =
      'attendance_expected_days_term';
  static const String keyAttendanceExpectedDaysYear =
      'attendance_expected_days_year';
  static const String keyAttendanceExpectedDaysHybridMonth =
      'attendance_expected_days_hybrid_month';
  static const String keyAttendanceExpectedDaysHybridTerm =
      'attendance_expected_days_hybrid_term';
  static const String keyAttendanceExpectedDaysHybridYear =
      'attendance_expected_days_hybrid_year';
  static const String keyAttendanceHolidays = 'attendance_holidays';
  static const String keyCurrentAcademicSession = 'current_academic_session';

  static const _tuitionKeys = {
    keyMonthlyTuitionFee,
    keyLumpSumDiscountPercent,
  };

  static const _attendanceThresholdKeys = {
    keyAttendanceExpectedDaysMonth,
    keyAttendanceExpectedDaysTerm,
    keyAttendanceExpectedDaysYear,
    keyAttendanceExpectedDaysHybridMonth,
    keyAttendanceExpectedDaysHybridTerm,
    keyAttendanceExpectedDaysHybridYear,
    keyAttendanceHolidays,
  };

  /// Keys that replicate across devices via change-sets.
  static const syncableKeys = {
    keyMonthlyTuitionFee,
    keyLumpSumDiscountPercent,
    keyAttendanceExpectedDaysMonth,
    keyAttendanceExpectedDaysTerm,
    keyAttendanceExpectedDaysYear,
    keyAttendanceExpectedDaysHybridMonth,
    keyAttendanceExpectedDaysHybridTerm,
    keyAttendanceExpectedDaysHybridYear,
    keyAttendanceHolidays,
    keyCurrentAcademicSession,
  };

  /// Device-local keys that must never be synced.
  static const deviceLocalKeys = {
    keyOnedriveUrl,
  };

  Future<String> _effectiveChangeSetDeviceId(String? deviceId) async {
    final d = deviceId?.trim();
    if (d != null && d.isNotEmpty && d != 'legacy') return d;
    return SyncFolderConfig.getOrCreateDeviceId();
  }

  /// Writes 2026 Full-time/Hybrid holiday seed when [keyAttendanceHolidays]
  /// is missing. Does not overwrite admin edits and does not emit a change-set.
  Future<void> ensureAttendanceHolidaysSeeded() async {
    final existing = await get(keyAttendanceHolidays);
    if (existing != null && existing.trim().isNotEmpty) return;
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: keyAttendanceHolidays,
            value: Value(AttendanceHolidaysByMode.seed2026.toJsonString()),
          ),
        );
  }

  /// Gets a setting value by key. Returns null if not set.
  Future<String?> get(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  /// Sets a setting value. If [value] is null, deletes the row.
  /// Tuition and attendance-threshold keys require [userRole]; sync/OneDrive keys
  /// do not require a role gate.
  /// Pass [userId]/[deviceId] to emit a sync change-set for [syncableKeys].
  Future<void> set(
    String key,
    String? value, {
    UserRole? userRole,
    String? userId,
    String? deviceId,
    String? userDisplayName,
    String? screen,
  }) async {
    if (_tuitionKeys.contains(key)) {
      if (userRole == null ||
          !RolePermissions.canManageFinancials(userRole)) {
        throw StateError('Role cannot manage financial settings');
      }
    } else if (_attendanceThresholdKeys.contains(key)) {
      if (userRole == null ||
          !RolePermissions.canManageAcademicSession(userRole)) {
        throw StateError('Role cannot manage attendance threshold settings');
      }
    }
    final nowIso = DateTime.now().toUtc().toIso8601String();
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
    if (userId != null && syncableKeys.contains(key)) {
      await _insertChangeSet(
        table: 'app_settings',
        recordId: key,
        operation: value == null ? 'DELETE' : 'UPDATE',
        payload: {
          'key': key,
          if (value != null) 'value': value,
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

  /// Stream of a setting value (reactive). Returns null if not set.
  Stream<String?> watch(String key) {
    return (_db.select(_db.appSettings)..where((s) => s.key.equals(key)))
        .watch()
        .map((rows) => rows.isEmpty ? null : rows.first.value);
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
