import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/seed_provider.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/widgets/shell/app_footer.dart';

import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/services/sync_folder_watch_coordinator.dart';

/// App shell: header, sidebar, main content, footer.
/// Used as ShellRoute child builder; [child] is the current route's content.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _startupSyncScheduled = false;
  late final SyncFolderWatchCoordinator _autoSyncCoordinator;

  @override
  void initState() {
    super.initState();
    _autoSyncCoordinator = SyncFolderWatchCoordinator(
      onSyncRequested: () => runChangeSetFullSyncForWidget(ref),
    );
  }

  @override
  void dispose() {
    _autoSyncCoordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_startupSyncScheduled) {
      _startupSyncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupSync());
    }

    // Run one-time seeds for first-, second-, and third-year (full-time/hybrid) when shell loads
    ref.watch(firstYearFullTimeSeedProvider);
    ref.watch(firstYearHybridSeedProvider);
    ref.watch(secondYearFtSeedProvider);
    ref.watch(secondYearFullTimeSeedProvider);
    ref.watch(thirdYearFtSeedProvider);
    ref.watch(thirdYearHybridSeedProvider);
    ref.watch(seedFirstAdminProvider);
    ref.watch(seedFacilitatorUsersProvider);

    final colorScheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authStateProvider).valueOrNull;
    final config = ref.watch(syncFolderConfigProvider).valueOrNull;
    final deviceId = ref.watch(deviceIdProvider).valueOrNull;
    if (deviceId != null && deviceId.isNotEmpty) {
      _autoSyncCoordinator.configure(
        syncFolderPath: config?.syncFolderPath,
        enabled: config?.autoSyncOnRemoteChange ?? true,
        localDeviceId: deviceId,
      );
    } else {
      _autoSyncCoordinator.stop();
    }
    final displayName = auth is Authenticated ? auth.user.displayName : 'User';
    final roleLabel = auth is Authenticated ? auth.role.displayName : '';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          _buildHeader(context, ref, displayName, roleLabel),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebar(context, ref),
                Expanded(child: widget.child),
              ],
            ),
          ),
          const AppFooter(),
        ],
      ),
    );
  }

  /// Run change-set sync once after the shell is visible (export then import).
  Future<void> _runStartupSync() async {
    try {
      await runChangeSetFullSyncForWidget(ref);
    } catch (e) {
      // Status is already updated by runChangeSetFullSync.
    }
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, String displayName, String roleLabel) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final headerBgColor = isDark ? AppColors.surfaceDarkElevated : AppColors.charisRedPrimary;
    final headerTextColor = isDark ? AppColors.textOnDark : AppColors.charisWhite;
    final headerTitleColor = isDark ? AppColors.primaryActionRed : AppColors.charisWhite;
    final headerRoleColor = isDark ? AppColors.textSecondaryOnDark : AppColors.charisWhite.withValues(alpha: 0.8);
    
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: headerBgColor,
      ),
      child: Row(
        children: [
          _buildLogo(context, isDark),
          const SizedBox(width: 12),
          Text(
            'Charis Student Care',
            style: TextStyle(
              color: headerTitleColor,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              fontFamily: 'Questrial',
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            color: headerTextColor,
            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
          ),
          const SizedBox(width: 8),
          _buildSyncedPill(context, ref),
          const SizedBox(width: 16),
          Icon(Icons.person_outline, color: headerTextColor, size: 24),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: TextStyle(
                  color: headerTextColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
              if (roleLabel.isNotEmpty)
                Text(
                  roleLabel,
                  style: TextStyle(
                    color: headerRoleColor,
                    fontSize: 12,
                    fontFamily: 'Questrial',
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => ref.read(authStateProvider.notifier).signOut(),
            icon: const Icon(Icons.logout_outlined),
            color: headerTextColor,
            tooltip: 'Log out',
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context, bool isDark) {
    final logoPath = isDark 
        ? 'assets/images/logo_dark.png'
        : 'assets/images/logo_light.png';
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.asset(
        logoPath,
        width: 36,
        height: 36,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          Icons.school,
          color: isDark ? AppColors.primaryActionRed : AppColors.charisWhite,
          size: 32,
        ),
      ),
    );
  }

  bool _canManageUsers(WidgetRef ref) {
    final auth = ref.watch(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return false;
    return RolePermissions.canManageUsers(auth.role);
  }

  bool _canManageMissions(WidgetRef ref) {
    final auth = ref.watch(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return false;
    return RolePermissions.canManageMissions(auth.role);
  }

  /// True only for roles that may open Payments and Missions Payment screens (e.g. adminLevel01).
  /// Facilitators must not see the sidebar links to those screens.
  bool _canAccessPaymentScreens(WidgetRef ref) {
    final auth = ref.watch(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return false;
    return RolePermissions.canManageFinancials(auth.role);
  }

  /// True only for roles that may access Export & Reports.
  bool _canExportReports(WidgetRef ref) {
    final auth = ref.watch(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return false;
    return RolePermissions.canExportReports(auth.role);
  }

  Widget _buildSyncedPill(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(syncFolderConfigProvider);
    final syncStatus = ref.watch(changeSetSyncStatusProvider);
    final deviceId = ref.watch(deviceIdProvider).valueOrNull;
    final changeSetsAsync = deviceId != null
        ? ref.watch(changeSetsForDeviceProvider(deviceId))
        : const AsyncValue.data(<ChangeSet>[]);
    final conflictCountAsync = ref.watch(syncConflictsCountStreamProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;

    final hasSyncFolder = configAsync.valueOrNull?.syncFolderPath != null &&
        configAsync.valueOrNull!.syncFolderPath!.trim().isNotEmpty;
    final isSyncing = syncStatus.isSyncing;
    final hasError = syncStatus.hasError;
    final conflictCount = conflictCountAsync.valueOrNull ?? 0;
    final changeSets = changeSetsAsync.valueOrNull ?? <ChangeSet>[];
    final lastSync = syncStatus.lastSyncTime;
    final hasPending = lastSync == null
        ? changeSets.isNotEmpty
        : changeSets.any((c) => c.timestamp.isAfter(lastSync));

    Color backgroundColor;
    String label;
    Color labelColor;

    if (isSyncing) {
      backgroundColor = isDark ? AppColors.surfaceDarkElevated : AppColors.charisLightGray;
      label = 'OneDrive syncing...';
      labelColor = isDark ? AppColors.textSecondaryOnDark : AppColors.charisDarkGray;
    } else if (hasError) {
      backgroundColor = AppColors.charisRedDark;
      label = 'OneDrive sync failed';
      labelColor = AppColors.charisWhite;
    } else if (conflictCount > 0) {
      backgroundColor = AppColors.charisRedDark;
      label = conflictCount == 1 ? '1 conflict' : '$conflictCount conflicts';
      labelColor = AppColors.charisWhite;
    } else if (hasPending) {
      backgroundColor = isDark ? AppColors.surfaceDarkElevated : AppColors.charisLightGray;
      label = 'Pending';
      labelColor = isDark ? AppColors.textSecondaryOnDark : AppColors.charisDarkGray;
    } else if (hasSyncFolder) {
      backgroundColor = AppColors.syncedGreen;
      label = 'OneDrive synced';
      labelColor = AppColors.charisWhite;
    } else {
      backgroundColor = isDark ? AppColors.surfaceDarkElevated : AppColors.charisLightGray;
      label = 'No sync folder';
      labelColor = isDark ? AppColors.textSecondaryOnDark : AppColors.charisDarkGray;
    }

    final lastSyncLabel = lastSync != null
        ? ' · ${lastSync.hour.toString().padLeft(2, '0')}:${lastSync.minute.toString().padLeft(2, '0')}'
        : '';

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isSyncing)
            ...[
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(labelColor),
                ),
              ),
              const SizedBox(width: 6),
            ],
          Text(
            label + lastSyncLabel,
            style: TextStyle(
              color: labelColor,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              fontFamily: 'Questrial',
            ),
          ),
        ],
      ),
    );

    final errorMessage = syncStatus.lastError?.trim();
    if (hasError && errorMessage != null && errorMessage.isNotEmpty) {
      return Tooltip(
        message: errorMessage,
        waitDuration: const Duration(milliseconds: 400),
        child: pill,
      );
    }
    return pill;
  }

  Widget _buildSidebar(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final sidebarBgColor = isDark ? AppColors.surfaceDarkElevated : AppColors.charisRedPrimary;
    
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: sidebarBgColor,
      ),
      child: SingleChildScrollView(
        child: Column(
          children: [
            _navItem(context, ref, Icons.dashboard_outlined, Icons.dashboard, 'Dashboard', '/dashboard'),
            _navItem(context, ref, Icons.people_outline, Icons.people, 'Students', '/students'),
            _navItem(context, ref, Icons.book_outlined, Icons.book, 'Subjects', '/subjects'),
            _navItem(context, ref, Icons.checklist_outlined, Icons.checklist, 'Attendance', '/attendance'),
            _navItem(context, ref, Icons.hourglass_empty_outlined, Icons.hourglass_empty, 'Ministry Hours', '/ministry-hours'),
            _navItem(context, ref, Icons.assignment_outlined, Icons.assignment, 'Tests', '/tests'),
            if (_canAccessPaymentScreens(ref)) ...[
              _navItem(context, ref, Icons.credit_card_outlined, Icons.credit_card, 'Finances', '/payments'),
              _navItem(context, ref, Icons.flight_takeoff_outlined, Icons.flight_takeoff, 'Missions Payment', '/missions-payment'),
            ],
            if (_canManageMissions(ref)) ...[
              _navItem(context, ref, Icons.flight_outlined, Icons.flight, 'Missions', '/missions'),
              _navItem(context, ref, Icons.place_outlined, Icons.place, 'Mission Locations', '/mission-locations'),
            ],
            if (_canExportReports(ref))
              _navItem(context, ref, Icons.download_outlined, Icons.download, 'Export & Reports', '/reports'),
            _navItem(context, ref, Icons.history_outlined, Icons.history, 'Recent Activities', '/activities'),
            _navItem(context, ref, Icons.settings_outlined, Icons.settings, 'Settings', '/settings'),
            if (_canManageUsers(ref))
              _navItem(context, ref, Icons.people_outline, Icons.people, 'Users', '/users'),
          ],
        ),
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    WidgetRef ref,
    IconData iconOutlined,
    IconData iconFilled,
    String label,
    String path,
  ) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final selected = GoRouterState.of(context).matchedLocation == path;
    
    final textColor = isDark
        ? (selected ? AppColors.primaryActionRed : AppColors.textOnDark)
        : AppColors.charisWhite;
    final borderColor = isDark
        ? AppColors.primaryActionRed
        : AppColors.charisWhite;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () => context.go(path),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            decoration: BoxDecoration(
              border: selected
                  ? Border(
                      left: BorderSide(
                        color: borderColor,
                        width: 3,
                      ),
                    )
                  : null,
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  selected ? iconFilled : iconOutlined,
                  size: 22,
                  color: textColor,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
