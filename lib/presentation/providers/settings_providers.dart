import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/app_settings_repository.dart';
import 'package:charis_student_care/domain/attendance/attendance_thresholds.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';

/// Provider for AppSettingsRepository.
final settingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return AppSettingsRepository(
    db,
    onLocalChangeSetWritten: () =>
        ref.read(postCrudSyncSchedulerProvider).schedule(),
  );
});

/// Reactive stream of the stored OneDrive URL. Returns null if not set.
final onedriveUrlStreamProvider = StreamProvider.autoDispose<String?>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return repo.watch(AppSettingsRepository.keyOnedriveUrl);
});

/// Notifier for saving the OneDrive URL. Call [saveOneDriveUrl] to persist.
class OneDriveUrlNotifier {
  OneDriveUrlNotifier(this._repo);
  final AppSettingsRepository _repo;

  Future<void> saveOneDriveUrl(String? value) =>
      _repo.set(AppSettingsRepository.keyOnedriveUrl, value);
}

final onedriveUrlNotifierProvider =
    Provider.autoDispose<OneDriveUrlNotifier>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return OneDriveUrlNotifier(repo);
});

const double defaultMonthlyTuitionFee = 2250.0;
const double defaultLumpSumDiscountPercent = 9.09;
const int sessionFinanceMonthCount = 9;

final monthlyTuitionFeeProvider = StreamProvider.autoDispose<double>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return repo.watch(AppSettingsRepository.keyMonthlyTuitionFee).map((value) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
      return defaultMonthlyTuitionFee;
    }
    return parsed;
  });
});

final lumpSumDiscountPercentProvider = StreamProvider.autoDispose<double>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return repo.watch(AppSettingsRepository.keyLumpSumDiscountPercent).map((value) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null || parsed.isNaN || parsed.isInfinite) {
      return defaultLumpSumDiscountPercent;
    }
    return parsed.clamp(0.0, 100.0);
  });
});

final sessionTuitionAmountProvider = Provider.autoDispose<double>((ref) {
  final monthly = ref.watch(monthlyTuitionFeeProvider).valueOrNull ??
      defaultMonthlyTuitionFee;
  return monthly * sessionFinanceMonthCount;
});

final discountedLumpSumTuitionAmountProvider = Provider.autoDispose<double>((ref) {
  final sessionTuition = ref.watch(sessionTuitionAmountProvider);
  final discountPercent = ref.watch(lumpSumDiscountPercentProvider).valueOrNull ??
      defaultLumpSumDiscountPercent;
  final discountFactor = (100.0 - discountPercent.clamp(0.0, 100.0)) / 100.0;
  return sessionTuition * discountFactor;
});

int _parseExpectedDays(String? value, int fallback) {
  final parsed = int.tryParse((value ?? '').trim());
  if (parsed == null || parsed < 0) return fallback;
  return parsed;
}

const _attendanceThresholdSettingKeys = [
  AppSettingsRepository.keyAttendanceExpectedDaysMonth,
  AppSettingsRepository.keyAttendanceExpectedDaysTerm,
  AppSettingsRepository.keyAttendanceExpectedDaysYear,
  AppSettingsRepository.keyAttendanceExpectedDaysHybridMonth,
  AppSettingsRepository.keyAttendanceExpectedDaysHybridTerm,
  AppSettingsRepository.keyAttendanceExpectedDaysHybridYear,
];

AttendanceThresholdsByMode _thresholdsFromSettingRows(
  Iterable<AppSetting> rows,
) {
  final map = <String, String?>{
    for (final row in rows) row.key: row.value,
  };
  return AttendanceThresholdsByMode(
    fullTime: AttendanceThresholdConfig(
      month: _parseExpectedDays(
        map[AppSettingsRepository.keyAttendanceExpectedDaysMonth],
        AppConstants.attendanceExpectedDaysPerMonth,
      ),
      term: _parseExpectedDays(
        map[AppSettingsRepository.keyAttendanceExpectedDaysTerm],
        AppConstants.attendanceExpectedDaysPerTerm,
      ),
      year: _parseExpectedDays(
        map[AppSettingsRepository.keyAttendanceExpectedDaysYear],
        AppConstants.attendanceExpectedDaysPerYear,
      ),
    ),
    hybrid: AttendanceThresholdConfig(
      month: _parseExpectedDays(
        map[AppSettingsRepository.keyAttendanceExpectedDaysHybridMonth],
        AppConstants.attendanceExpectedDaysHybridPerMonth,
      ),
      term: _parseExpectedDays(
        map[AppSettingsRepository.keyAttendanceExpectedDaysHybridTerm],
        AppConstants.attendanceExpectedDaysHybridPerTerm,
      ),
      year: _parseExpectedDays(
        map[AppSettingsRepository.keyAttendanceExpectedDaysHybridYear],
        AppConstants.attendanceExpectedDaysHybridPerYear,
      ),
    ),
  );
}

/// Reactive Full-time and Hybrid attendance expected-day thresholds.
final attendanceThresholdsByModeProvider =
    StreamProvider.autoDispose<AttendanceThresholdsByMode>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return (db.select(db.appSettings)
        ..where((t) => t.key.isIn(_attendanceThresholdSettingKeys)))
      .watch()
      .map(_thresholdsFromSettingRows);
});
