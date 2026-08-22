import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/services/change_set_applier.dart';
import 'package:charis_student_care/data/repositories/academic_session_repository.dart';
import 'package:charis_student_care/data/repositories/app_settings_repository.dart';
import 'package:charis_student_care/domain/attendance/attendance_thresholds.dart';
import 'package:charis_student_care/presentation/providers/academic_session_providers.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/providers/settings_providers.dart';
import 'package:charis_student_care/presentation/widgets/academic_session_form_dialog.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:charis_student_care/presentation/widgets/conflict_resolution_dialog.dart';

/// Settings screen: Sync folder path and Sync now.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _pathController = TextEditingController();
  final _monthlyTuitionController = TextEditingController();
  final _lumpSumDiscountController = TextEditingController();
  final _attendanceMonthController = TextEditingController();
  final _attendanceTermController = TextEditingController();
  final _attendanceYearController = TextEditingController();
  final _hybridAttendanceMonthController = TextEditingController();
  final _hybridAttendanceTermController = TextEditingController();
  final _hybridAttendanceYearController = TextEditingController();
  bool _isSaving = false;
  bool _isResolvingAll = false;
  bool _tuitionFieldsInitialized = false;
  bool _attendanceFieldsInitialized = false;

  @override
  void dispose() {
    _pathController.dispose();
    _monthlyTuitionController.dispose();
    _lumpSumDiscountController.dispose();
    _attendanceMonthController.dispose();
    _attendanceTermController.dispose();
    _attendanceYearController.dispose();
    _hybridAttendanceMonthController.dispose();
    _hybridAttendanceTermController.dispose();
    _hybridAttendanceYearController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final configAsync = ref.watch(syncFolderConfigProvider);
    final syncStatus = ref.watch(changeSetSyncStatusProvider);
    final monthlyTuitionAsync = ref.watch(monthlyTuitionFeeProvider);
    final discountPercentAsync = ref.watch(lumpSumDiscountPercentProvider);
    final attendanceThresholdsAsync =
        ref.watch(attendanceThresholdsByModeProvider);

    ref.listen<AsyncValue<SyncFolderConfig>>(syncFolderConfigProvider, (prev, next) {
      next.whenData((config) {
        if (_pathController.text != (config.syncFolderPath ?? '')) {
          _pathController.text = config.syncFolderPath ?? '';
        }
      });
    });

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Settings',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 24,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Configure application preferences and sync.',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSyncSection(context, colorScheme, redColor, configAsync, syncStatus.isSyncing),
                  RoleGuard(
                    canShow: RolePermissions.canManageFinancials,
                    child: _buildTuitionSection(
                      context,
                      colorScheme,
                      redColor,
                      monthlyTuitionAsync,
                      discountPercentAsync,
                    ),
                  ),
                  RoleGuard(
                    canShow: RolePermissions.canManageAcademicSession,
                    child: _buildAttendanceThresholdSection(
                      context,
                      colorScheme,
                      redColor,
                      attendanceThresholdsAsync,
                    ),
                  ),
                  RoleGuard(
                    canShow: RolePermissions.canManageAcademicSession,
                    child: _buildAcademicSessionSection(context, colorScheme, redColor),
                  ),
                  _buildConflictsSection(context, colorScheme, redColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncSection(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    AsyncValue<SyncFolderConfig> configAsync,
    bool isSyncing,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sync folder',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a folder inside your OneDrive so all devices can sync (e.g. OneDrive\\CharisStudentCare\\Sync). Each device needs OneDrive desktop installed.',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 16),
        configAsync.when(
          data: (config) {
            if (_pathController.text.isEmpty && config.syncFolderPath != null && config.syncFolderPath!.isNotEmpty) {
              _pathController.text = config.syncFolderPath!;
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _pathController,
                    decoration: InputDecoration(
                      labelText: 'Sync folder path',
                      hintText: 'C:\\Users\\...\\OneDrive\\CharisStudentCare\\Sync',
                      border: const OutlineInputBorder(),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                    ),
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontFamily: 'Questrial',
                    ),
                    enabled: !_isSaving,
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _isSaving ? null : () => _browseFolder(),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Browse'),
                  style: FilledButton.styleFrom(
                    backgroundColor: redColor,
                    foregroundColor: colorScheme.onPrimary,
                    textStyle: const TextStyle(fontFamily: 'Questrial'),
                  ),
                ),
              ],
            );
          },
          loading: () => const SizedBox(height: 56),
          error: (_, __) => const SizedBox(height: 56),
        ),
        const SizedBox(height: 16),
        configAsync.when(
          data: (config) {
            return SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Auto-sync when sync files change',
                style: TextStyle(fontFamily: 'Questrial'),
              ),
              subtitle: Text(
                'Automatically sync when OneDrive updates device_*.json files from other devices.',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontFamily: 'Questrial',
                ),
              ),
              value: config.autoSyncOnRemoteChange,
              onChanged: _isSaving ? null : (v) => _saveAutoSync(v, colorScheme),
              activeThumbColor: redColor,
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isSaving ? null : () => _saveSyncPath(colorScheme),
            icon: _isSaving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? 'Saving...' : 'Save path'),
            style: FilledButton.styleFrom(
              backgroundColor: redColor,
              foregroundColor: colorScheme.onPrimary,
              textStyle: const TextStyle(fontFamily: 'Questrial'),
            ),
          ),
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: isSyncing ? null : () => _syncNow(context, colorScheme),
            icon: isSyncing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.sync),
            label: Text(isSyncing ? 'Syncing...' : 'Sync now'),
            style: FilledButton.styleFrom(
              backgroundColor: redColor,
              foregroundColor: colorScheme.onPrimary,
              textStyle: const TextStyle(fontFamily: 'Questrial'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAttendanceThresholdSection(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    AsyncValue<AttendanceThresholdsByMode> thresholdsAsync,
  ) {
    if (!_attendanceFieldsInitialized) {
      final byMode =
          thresholdsAsync.valueOrNull ?? AttendanceThresholdsByMode.defaults;
      _attendanceMonthController.text = byMode.fullTime.month.toString();
      _attendanceTermController.text = byMode.fullTime.term.toString();
      _attendanceYearController.text = byMode.fullTime.year.toString();
      _hybridAttendanceMonthController.text = byMode.hybrid.month.toString();
      _hybridAttendanceTermController.text = byMode.hybrid.term.toString();
      _hybridAttendanceYearController.text = byMode.hybrid.year.toString();
      _attendanceFieldsInitialized = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'Attendance expected days',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Expected present days used for month / term / session thresholds. Full-time and Hybrid are stored separately.',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Full-time',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 12),
        _attendanceExpectedDaysFields(
          monthController: _attendanceMonthController,
          termController: _attendanceTermController,
          yearController: _attendanceYearController,
        ),
        const SizedBox(height: 24),
        Text(
          'Hybrid',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Term is typically 6, Month is typically 2 and session is typically 18',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 12),
        _attendanceExpectedDaysFields(
          monthController: _hybridAttendanceMonthController,
          termController: _hybridAttendanceTermController,
          yearController: _hybridAttendanceYearController,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isSaving
                ? null
                : () => _saveAttendanceThresholdSettings(colorScheme),
            icon: _isSaving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(
                _isSaving ? 'Saving...' : 'Save attendance thresholds',),
            style: FilledButton.styleFrom(
              backgroundColor: redColor,
              foregroundColor: colorScheme.onPrimary,
              textStyle: const TextStyle(fontFamily: 'Questrial'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _attendanceExpectedDaysFields({
    required TextEditingController monthController,
    required TextEditingController termController,
    required TextEditingController yearController,
  }) {
    return Column(
      children: [
        TextField(
          controller: monthController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Expected days per month',
            border: OutlineInputBorder(),
          ),
          enabled: !_isSaving,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: termController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Expected days per term',
            border: OutlineInputBorder(),
          ),
          enabled: !_isSaving,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: yearController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Expected days per session',
            border: OutlineInputBorder(),
          ),
          enabled: !_isSaving,
        ),
      ],
    );
  }

  Widget _buildAcademicSessionSection(BuildContext context, ColorScheme colorScheme, Color redColor) {
    final sessionsAsync = ref.watch(allAcademicSessionsStreamProvider);
    final currentAsync = ref.watch(currentAcademicSessionProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'Academic session',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Set the current session and manage sessions (one year Feb–Oct, e.g. 2026). Only admin can change these.',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 16),
        currentAsync.when(
          data: (currentCode) {
            return sessionsAsync.when(
              data: (sessions) {
                final codes = sessions.map((s) => s.code).toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'Current session:',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 13,
                            fontFamily: 'Questrial',
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (codes.isEmpty)
                          Text(
                            currentCode ?? 'None set',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13,
                              fontFamily: 'Questrial',
                            ),
                          )
                        else
                          DropdownButton<String>(
                            value: codes.contains(currentCode ?? '') ? currentCode : codes.first,
                            items: codes.map((c) => DropdownMenuItem<String>(value: c, child: Text(c))).toList(),
                            onChanged: (v) async {
                              if (v == null) return;
                              final auth = ref.read(authStateProvider).valueOrNull;
                              final deviceId =
                                  await ref.read(deviceIdProvider.future);
                              await ref.read(academicSessionRepositoryProvider).setCurrentSession(
                                    v,
                                    userRole: auth is Authenticated
                                        ? auth.role
                                        : UserRole.facilitator,
                                    userId: auth is Authenticated
                                        ? auth.user.id
                                        : null,
                                    deviceId: deviceId,
                                    userDisplayName: auth is Authenticated
                                        ? auth.user.displayName
                                        : null,
                                    screen: 'Settings',
                                  );
                              ref.invalidate(currentAcademicSessionProvider);
                              ref.invalidate(academicSessionOptionsProvider);
                            },
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 13,
                              fontFamily: 'Questrial',
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: () => AcademicSessionFormDialog.showAdd(
                          context: context,
                          ref: ref,
                          onSaved: () {
                            ref.invalidate(allAcademicSessionsStreamProvider);
                            ref.invalidate(academicSessionOptionsProvider);
                            ref.invalidate(currentAcademicSessionProvider);
                          },
                        ),
                        icon: const Icon(Icons.add_outlined, size: 20),
                        label: const Text('Add session'),
                        style: FilledButton.styleFrom(
                          backgroundColor: redColor,
                          foregroundColor: colorScheme.onPrimary,
                          textStyle: const TextStyle(fontFamily: 'Questrial'),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (sessions.isNotEmpty)
                      ...sessions.map((s) => _buildSessionCard(context, colorScheme, redColor, s)),
                  ],
                );
              },
              loading: () => const SizedBox(height: 48),
              error: (e, _) => Text('Error: $e', style: TextStyle(color: colorScheme.error, fontSize: 12)),
            );
          },
          loading: () => const SizedBox(height: 24),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildTuitionSection(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    AsyncValue<double> monthlyTuitionAsync,
    AsyncValue<double> discountPercentAsync,
  ) {
    if (!_tuitionFieldsInitialized) {
      final monthly = monthlyTuitionAsync.valueOrNull ?? defaultMonthlyTuitionFee;
      final discount = discountPercentAsync.valueOrNull ?? defaultLumpSumDiscountPercent;
      _monthlyTuitionController.text = monthly.toStringAsFixed(2);
      _lumpSumDiscountController.text = discount.toStringAsFixed(2);
      _tuitionFieldsInitialized = true;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 16),
        Text(
          'Tuition settings',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Set monthly tuition and full-session lump-sum discount for the 9-month Feb–Oct session.',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _monthlyTuitionController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Monthly tuition fee (R)',
            border: OutlineInputBorder(),
          ),
          enabled: !_isSaving,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _lumpSumDiscountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Lump-sum discount (%)',
            border: OutlineInputBorder(),
          ),
          enabled: !_isSaving,
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isSaving ? null : () => _saveTuitionSettings(colorScheme),
            icon: _isSaving
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_isSaving ? 'Saving...' : 'Save tuition settings'),
            style: FilledButton.styleFrom(
              backgroundColor: redColor,
              foregroundColor: colorScheme.onPrimary,
              textStyle: const TextStyle(fontFamily: 'Questrial'),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionCard(BuildContext context, ColorScheme colorScheme, Color redColor, AcademicSessionRecord s) {
    String dateRange = '';
    if (s.startDate != null || s.endDate != null) {
      final start = s.startDate != null
          ? '${s.startDate!.year}-${s.startDate!.month.toString().padLeft(2, '0')}-${s.startDate!.day.toString().padLeft(2, '0')}'
          : '?';
      final end = s.endDate != null
          ? '${s.endDate!.year}-${s.endDate!.month.toString().padLeft(2, '0')}-${s.endDate!.day.toString().padLeft(2, '0')}'
          : '?';
      dateRange = '$start – $end';
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        s.code,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          fontFamily: 'Questrial',
                        ),
                      ),
                      if (s.isActive) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Current',
                            style: TextStyle(
                              color: colorScheme.onPrimaryContainer,
                              fontSize: 11,
                              fontFamily: 'Questrial',
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (s.displayName != null && s.displayName!.trim().isNotEmpty)
                    Text(
                      s.displayName!.trim(),
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontFamily: 'Questrial',
                      ),
                    ),
                  if (dateRange.isNotEmpty)
                    Text(
                      dateRange,
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontFamily: 'Questrial',
                      ),
                    ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => AcademicSessionFormDialog.showEdit(
                context: context,
                ref: ref,
                record: s,
                onSaved: () {
                  ref.invalidate(allAcademicSessionsStreamProvider);
                  ref.invalidate(academicSessionOptionsProvider);
                  ref.invalidate(currentAcademicSessionProvider);
                },
              ),
              child: const Text('Edit'),
            ),
            if (!s.isActive)
              TextButton(
                onPressed: () async {
                  final auth = ref.read(authStateProvider).valueOrNull;
                  final deviceId = await ref.read(deviceIdProvider.future);
                  await ref.read(academicSessionRepositoryProvider).setCurrentSession(
                        s.code,
                        userRole: auth is Authenticated
                            ? auth.role
                            : UserRole.facilitator,
                        userId: auth is Authenticated ? auth.user.id : null,
                        deviceId: deviceId,
                        userDisplayName: auth is Authenticated
                            ? auth.user.displayName
                            : null,
                        screen: 'Settings',
                      );
                  ref.invalidate(currentAcademicSessionProvider);
                  ref.invalidate(academicSessionOptionsProvider);
                  ref.invalidate(allAcademicSessionsStreamProvider);
                },
                child: const Text('Set current'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildConflictsSection(BuildContext context, ColorScheme colorScheme, Color redColor) {
    return RoleGuard(
      canShow: RolePermissions.canResolveConflicts,
      child: _buildConflictsSectionContent(context, colorScheme, redColor),
    );
  }

  Widget _buildConflictsSectionContent(
      BuildContext context, ColorScheme colorScheme, Color redColor,) {
    final conflictsAsync = ref.watch(syncConflictsListStreamProvider);
    return conflictsAsync.when(
      data: (conflicts) {
        if (conflicts.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Sync conflicts',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Critical changes from another device conflict with your data. Resolve as Admin Level 01.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _isResolvingAll
                      ? null
                      : () => _resolveAllKeepLocal(colorScheme),
                  icon: _isResolvingAll
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.done_all_outlined, size: 18),
                  style: FilledButton.styleFrom(
                    backgroundColor: redColor,
                    foregroundColor: colorScheme.onPrimary,
                    textStyle: const TextStyle(fontFamily: 'Questrial'),
                  ),
                  label: const Text('Resolve all (Keep local)'),
                ),
                FilledButton.icon(
                  onPressed: _isResolvingAll
                      ? null
                      : () => _resolveAllUseIncoming(colorScheme),
                  icon: _isResolvingAll
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.warning_amber_outlined, size: 18),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.charisRedPrimary,
                    foregroundColor: colorScheme.onPrimary,
                    textStyle: const TextStyle(fontFamily: 'Questrial'),
                  ),
                  label: const Text('Resolve all (Use incoming)'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...conflicts.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${c.entityTable} · ${c.recordId}',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 13,
                            fontFamily: 'Questrial',
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: () => _openConflictResolution(context, c),
                        style: FilledButton.styleFrom(
                          backgroundColor: redColor,
                          foregroundColor: colorScheme.onPrimary,
                          textStyle: const TextStyle(fontFamily: 'Questrial'),
                        ),
                        child: const Text('Resolve'),
                      ),
                    ],
                  ),
                ),),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Future<void> _healKeepLocal(SyncConflict conflict) async {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return;
    final deviceId = await ref.read(deviceIdProvider.future);
    final db = ref.read(appDatabaseProvider);
    final applier = ChangeSetApplier(db);
    await applier.writeKeepLocalHealChangeSet(
      tableName: conflict.entityTable,
      recordId: conflict.recordId,
      userId: auth.user.id,
      deviceId: deviceId,
      localSnapshot: conflict.localSnapshot,
      onWritten: () => ref.read(postCrudSyncSchedulerProvider).schedule(),
    );
  }

  Future<void> _openConflictResolution(BuildContext context, SyncConflict conflict) async {
    final repo = ref.read(syncConflictsRepositoryProvider);
    final db = ref.read(appDatabaseProvider);
    final applier = ChangeSetApplier(db);
    await ConflictResolutionDialog.show(
      context,
      conflict: conflict,
      onKeepLocal: () async {
        await _healKeepLocal(conflict);
        await repo.resolveKeepLocal(conflict.id);
      },
      onUseIncoming: () async {
        await applier.applyIncomingPayloadForConflict(
          conflict.entityTable,
          conflict.recordId,
          conflict.incomingPayload,
        );
        await repo.resolveUseIncoming(conflict.id);
      },
    );
  }

  Future<bool> _confirmBulkResolution(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(
            message,
            style: const TextStyle(fontFamily: 'Questrial'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        );
      },
    );
    return confirmed ?? false;
  }

  Future<void> _resolveAllKeepLocal(ColorScheme colorScheme) async {
    final repo = ref.read(syncConflictsRepositoryProvider);
    final conflicts = await repo.listConflicts();
    if (conflicts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No unresolved conflicts found.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final confirmed = await _confirmBulkResolution(
      context,
      title: 'Resolve all conflicts',
      message:
          'Keep local values for all ${conflicts.length} unresolved conflict(s). Incoming values will be discarded.',
      confirmLabel: 'Keep local for all',
    );
    if (!confirmed) return;

    if (mounted) setState(() => _isResolvingAll = true);
    try {
      for (final conflict in conflicts) {
        await _healKeepLocal(conflict);
      }
      final deleted = await repo.resolveKeepLocalMany(conflicts.map((c) => c.id));
      ref.invalidate(syncConflictsCountProvider);
      ref.invalidate(syncConflictsListStreamProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Resolved $deleted conflict(s) by keeping local values.'),
            backgroundColor: AppColors.syncedGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bulk resolve failed: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResolvingAll = false);
    }
  }

  Future<void> _resolveAllUseIncoming(ColorScheme colorScheme) async {
    final repo = ref.read(syncConflictsRepositoryProvider);
    final db = ref.read(appDatabaseProvider);
    final applier = ChangeSetApplier(db);
    final conflicts = await repo.listConflicts();
    if (conflicts.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No unresolved conflicts found.'),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    final confirmed = await _confirmBulkResolution(
      context,
      title: 'Resolve all using incoming',
      message:
          'Apply incoming values for all ${conflicts.length} unresolved conflict(s). This can overwrite local data.',
      confirmLabel: 'Use incoming for all',
    );
    if (!confirmed) return;

    if (mounted) setState(() => _isResolvingAll = true);
    var resolved = 0;
    var failed = 0;
    try {
      for (final conflict in conflicts) {
        try {
          await applier.applyIncomingPayloadForConflict(
            conflict.entityTable,
            conflict.recordId,
            conflict.incomingPayload,
          );
          await repo.resolveUseIncoming(conflict.id);
          resolved++;
        } catch (_) {
          failed++;
        }
      }
      ref.invalidate(syncConflictsCountProvider);
      ref.invalidate(syncConflictsListStreamProvider);
      if (mounted) {
        final message = failed == 0
            ? 'Resolved $resolved conflict(s) using incoming values.'
            : 'Resolved $resolved conflict(s); $failed failed and remain unresolved.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: failed == 0 ? AppColors.syncedGreen : colorScheme.error,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bulk resolve failed: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResolvingAll = false);
    }
  }

  Future<void> _browseFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select sync folder (e.g. inside OneDrive)',
    );
    if (path != null && mounted) {
      _pathController.text = path;
    }
  }

  Future<void> _saveSyncPath(ColorScheme colorScheme) async {
    final path = _pathController.text.trim();
    setState(() => _isSaving = true);
    try {
      await SyncFolderConfig.saveSyncFolderPath(path.isEmpty ? null : path);
      ref.invalidate(syncFolderConfigProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync folder path saved.'),
            backgroundColor: AppColors.syncedGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _syncNow(BuildContext context, ColorScheme colorScheme) async {
    try {
      final applied = await runChangeSetFullSyncForWidget(
        ref,
        invalidateConflictCount: true,
      );
      if (mounted) {
        final conflictCount = await ref.read(syncConflictsCountProvider.future);
        if (!context.mounted) return;
        final message = applied > 0
            ? 'OneDrive synced. Applied $applied change-set(s).'
            : 'OneDrive sync complete. No new changes to apply.';
        final conflictNote = conflictCount > 0
            ? ' $conflictCount conflict(s) need resolution in Settings.'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$message$conflictNote'),
            backgroundColor: AppColors.syncedGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('OneDrive sync failed: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }

  Future<void> _saveAutoSync(bool enabled, ColorScheme colorScheme) async {
    setState(() => _isSaving = true);
    try {
      await SyncFolderConfig.saveAutoSyncOnRemoteChange(enabled);
      ref.invalidate(syncFolderConfigProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? 'Auto-sync on remote changes enabled.'
                  : 'Auto-sync on remote changes disabled.',
            ),
            backgroundColor: AppColors.syncedGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save auto-sync setting: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveTuitionSettings(ColorScheme colorScheme) async {
    final monthly = double.tryParse(_monthlyTuitionController.text.trim());
    final discount = double.tryParse(_lumpSumDiscountController.text.trim());
    if (monthly == null || monthly < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Monthly tuition must be a valid number (>= 0).'),
          backgroundColor: colorScheme.error,
        ),
      );
      return;
    }
    if (discount == null || discount < 0 || discount > 100) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Discount must be between 0 and 100.'),
          backgroundColor: colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(settingsRepositoryProvider);
      final auth = ref.read(authStateProvider).valueOrNull;
      final userRole = auth is Authenticated
          ? auth.role
          : UserRole.facilitator;
      final deviceId = await ref.read(deviceIdProvider.future);
      final userId = auth is Authenticated ? auth.user.id : null;
      final userDisplayName =
          auth is Authenticated ? auth.user.displayName : null;
      await repo.set(
        AppSettingsRepository.keyMonthlyTuitionFee,
        monthly.toString(),
        userRole: userRole,
        userId: userId,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: 'Settings',
      );
      await repo.set(
        AppSettingsRepository.keyLumpSumDiscountPercent,
        discount.toString(),
        userRole: userRole,
        userId: userId,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: 'Settings',
      );
      ref.invalidate(monthlyTuitionFeeProvider);
      ref.invalidate(lumpSumDiscountPercentProvider);
      ref.invalidate(sessionTuitionAmountProvider);
      ref.invalidate(discountedLumpSumTuitionAmountProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tuition settings saved.'),
            backgroundColor: AppColors.syncedGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save tuition settings: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveAttendanceThresholdSettings(ColorScheme colorScheme) async {
    final month = int.tryParse(_attendanceMonthController.text.trim());
    final term = int.tryParse(_attendanceTermController.text.trim());
    final year = int.tryParse(_attendanceYearController.text.trim());
    final hybridMonth =
        int.tryParse(_hybridAttendanceMonthController.text.trim());
    final hybridTerm =
        int.tryParse(_hybridAttendanceTermController.text.trim());
    final hybridYear =
        int.tryParse(_hybridAttendanceYearController.text.trim());
    final values = [month, term, year, hybridMonth, hybridTerm, hybridYear];
    if (values.any((v) => v == null || v < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Expected days must be valid integers (>= 0).'),
          backgroundColor: colorScheme.error,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(settingsRepositoryProvider);
      final auth = ref.read(authStateProvider).valueOrNull;
      final userRole = auth is Authenticated
          ? auth.role
          : UserRole.facilitator;
      final deviceId = await ref.read(deviceIdProvider.future);
      final userId = auth is Authenticated ? auth.user.id : null;
      final userDisplayName =
          auth is Authenticated ? auth.user.displayName : null;
      Future<void> saveKey(String key, int value) {
        return repo.set(
          key,
          value.toString(),
          userRole: userRole,
          userId: userId,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: 'Settings',
        );
      }

      await saveKey(AppSettingsRepository.keyAttendanceExpectedDaysMonth, month!);
      await saveKey(AppSettingsRepository.keyAttendanceExpectedDaysTerm, term!);
      await saveKey(AppSettingsRepository.keyAttendanceExpectedDaysYear, year!);
      await saveKey(
        AppSettingsRepository.keyAttendanceExpectedDaysHybridMonth,
        hybridMonth!,
      );
      await saveKey(
        AppSettingsRepository.keyAttendanceExpectedDaysHybridTerm,
        hybridTerm!,
      );
      await saveKey(
        AppSettingsRepository.keyAttendanceExpectedDaysHybridYear,
        hybridYear!,
      );
      ref.invalidate(attendanceThresholdsByModeProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Attendance thresholds saved.'),
            backgroundColor: AppColors.syncedGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save attendance thresholds: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
