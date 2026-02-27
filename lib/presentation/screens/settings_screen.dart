import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/config/sync_folder_config.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/services/change_set_applier.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
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
  bool _isSaving = false;

  @override
  void dispose() {
    _pathController.dispose();
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

  Widget _buildConflictsSection(BuildContext context, ColorScheme colorScheme, Color redColor) {
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
                      RoleGuard(
                        canShow: RolePermissions.canResolveConflicts,
                        child: FilledButton(
                          onPressed: () => _openConflictResolution(context, c),
                          style: FilledButton.styleFrom(
                            backgroundColor: redColor,
                            foregroundColor: colorScheme.onPrimary,
                            textStyle: const TextStyle(fontFamily: 'Questrial'),
                          ),
                          child: const Text('Resolve'),
                        ),
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

  Future<void> _openConflictResolution(BuildContext context, SyncConflict conflict) async {
    final repo = ref.read(syncConflictsRepositoryProvider);
    final db = ref.read(appDatabaseProvider);
    final applier = ChangeSetApplier(db);
    await ConflictResolutionDialog.show(
      context,
      conflict: conflict,
      onKeepLocal: () => repo.resolveKeepLocal(conflict.id),
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
    final status = ref.read(changeSetSyncStatusProvider.notifier);
    status.setSyncing(true);
    try {
      final syncService = ref.read(changeSetSyncServiceProvider);
      final db = ref.read(appDatabaseProvider);
      final applier = ChangeSetApplier(db);
      await syncService.export();
      final applied = await syncService.import(
        tryApply: (record) => applier.tryApply(record),
      );
      status.setSuccess();
      if (mounted) {
        ref.invalidate(syncConflictsCountProvider);
        final conflictCount = await ref.read(syncConflictsCountProvider.future);
        if (!context.mounted) return;
        final message = applied > 0
            ? 'Synced. Applied $applied change-set(s).'
            : 'Sync complete. No new changes to apply.';
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
      status.setError(e.toString());
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: $e'),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }
}
