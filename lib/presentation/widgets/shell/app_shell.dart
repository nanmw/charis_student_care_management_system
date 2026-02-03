import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/seed_provider.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/widgets/shell/app_footer.dart';

/// App shell: header, sidebar, main content, footer.
/// Used as ShellRoute child builder; [child] is the current route's content.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Run one-time seeds for first-, second-, and third-year (full-time/hybrid) when shell loads
    ref.watch(firstYearFullTimeSeedProvider);
    ref.watch(firstYearHybridSeedProvider);
    ref.watch(secondYearFtSeedProvider);
    ref.watch(secondYearFullTimeSeedProvider);
    ref.watch(thirdYearFtSeedProvider);
    ref.watch(thirdYearHybridSeedProvider);

    final colorScheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authStateProvider).valueOrNull;
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
                _buildSidebar(context),
                Expanded(child: child),
              ],
            ),
          ),
          const AppFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, String displayName, String roleLabel) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        children: [
          _buildLogo(context),
          const SizedBox(width: 12),
          Text(
            'Charis Student Care',
            style: TextStyle(
              color: AppColors.primaryActionRed,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              fontFamily: 'Questrial',
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            color: colorScheme.onSurface,
            tooltip: isDark ? 'Switch to light mode' : 'Switch to dark mode',
          ),
          const SizedBox(width: 8),
          _buildSyncedPill(context),
          const SizedBox(width: 16),
          Icon(Icons.person_outline, color: colorScheme.onSurface, size: 24),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
              if (roleLabel.isNotEmpty)
                Text(
                  roleLabel,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontFamily: 'Questrial',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.asset(
        'assets/images/logo.png',
        width: 36,
        height: 36,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          Icons.school,
          color: AppColors.primaryActionRed,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildSyncedPill(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.syncedGreen,
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Text(
        'Synced',
        style: TextStyle(
          color: AppColors.charisWhite,
          fontWeight: FontWeight.w600,
          fontSize: 12,
          fontFamily: 'Questrial',
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        children: [
          _navItem(context, Icons.dashboard_outlined, Icons.dashboard, 'Dashboard', '/dashboard'),
          _navItem(context, Icons.people_outline, Icons.people, 'Students', '/students'),
          _navItem(context, Icons.book_outlined, Icons.book, 'Subjects', '/subjects'),
          _navItem(context, Icons.checklist_outlined, Icons.checklist, 'Attendance', '/attendance'),
          _navItem(context, Icons.hourglass_empty_outlined, Icons.hourglass_empty, 'Ministry Hours', '/ministry-hours'),
          _navItem(context, Icons.assignment_outlined, Icons.assignment, 'Tests', '/tests'),
          _navItem(context, Icons.credit_card_outlined, Icons.credit_card, 'Payments', '/payments'),
          _navItem(context, Icons.public_outlined, Icons.public, 'Missions', '/missions'),
          _navItem(context, Icons.download_outlined, Icons.download, 'Reports / Export', '/reports'),
        ],
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    IconData iconOutlined,
    IconData iconFilled,
    String label,
    String path,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = GoRouterState.of(context).matchedLocation == path;
    final textColor = selected ? AppColors.primaryActionRed : colorScheme.onSurface;
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
                  ? const Border(
                      left: BorderSide(
                        color: AppColors.primaryActionRed,
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
