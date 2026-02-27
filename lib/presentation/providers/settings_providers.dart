import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/data/repositories/app_settings_repository.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

/// Provider for AppSettingsRepository.
final settingsRepositoryProvider = Provider<AppSettingsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return AppSettingsRepository(db);
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

/// Reactive stream: whether to show the Ministry Hours column on the dashboard.
/// Defaults to false (hidden) when not set.
final dashboardShowMinistryHoursProvider =
    StreamProvider.autoDispose<bool>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return repo
      .watch(AppSettingsRepository.keyDashboardShowMinistryHours)
      .map((v) => v == 'true');
});

/// Notifier to toggle the dashboard Ministry Hours column visibility.
class DashboardShowMinistryHoursNotifier {
  DashboardShowMinistryHoursNotifier(this._repo);
  final AppSettingsRepository _repo;

  Future<void> set(bool show) => _repo.set(
      AppSettingsRepository.keyDashboardShowMinistryHours,
      show ? 'true' : 'false',);
}

final dashboardShowMinistryHoursNotifierProvider =
    Provider.autoDispose<DashboardShowMinistryHoursNotifier>((ref) {
  final repo = ref.watch(settingsRepositoryProvider);
  return DashboardShowMinistryHoursNotifier(repo);
});
