import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:charis_student_care/core/utils/currency_utils.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/dashboard_providers.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/theme/app_table_style.dart';
import 'package:charis_student_care/presentation/widgets/student_summary_dialog.dart';

/// Status options for Individual tab filter (All, Active, Withdrawn, Transferred, Correspondence).
const List<String?> _individualStatusOptions = [
  null,
  'Active',
  'Withdrawn',
  'Transferred',
  'Correspondence',
];

/// Table cell helper for the cohort summary table (used by top-level _buildSummaryTable).
Widget _cohortSummaryTableCell(
  ColorScheme colorScheme,
  String text, {
  required bool isHeader,
  Color? backgroundColor,
}) {
  return Container(
    color: backgroundColor,
    padding: AppTableStyle.cellPadding,
    child: Text(
      text,
      style: isHeader
          ? AppTableStyle.headerTextStyle(colorScheme)
          : AppTableStyle.bodyTextStyle(colorScheme).copyWith(color: colorScheme.onSurfaceVariant),
    ),
  );
}

/// Builds the cohort (Class) summary table. [onViewCohort] is called when the user
/// clicks View for a row; used by _DashboardSummarySection to switch to Individual tab.
Widget _buildSummaryTable(
  BuildContext context,
  ColorScheme colorScheme,
  Color redColor,
  AsyncValue<List<DashboardCohortSummary>> cohortSummaryAsync,
  void Function(String year, String mode)? onViewCohort, {
  bool canShowBalance = true,
  int? hoveredRowIndex,
  void Function(int rowIndex)? onRowHoverEnter,
  void Function(int rowIndex)? onRowHoverExit,
}) {
  return cohortSummaryAsync.when(
    data: (summaries) {
      if (summaries.isEmpty) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Center(
            child: Text(
              'No cohort data to display.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
          ),
        );
      }
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
        ),
        child: Table(
          columnWidths: canShowBalance
              ? const {
                  0: FlexColumnWidth(0.6),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(1),
                  3: FlexColumnWidth(1.5),
                  4: FlexColumnWidth(1.5),
                  5: FlexColumnWidth(1),
                  6: FlexColumnWidth(1),
                  7: FlexColumnWidth(2),
                  8: FlexColumnWidth(0.8),
                }
              : const {
                  0: FlexColumnWidth(0.6),
                  1: FlexColumnWidth(2),
                  2: FlexColumnWidth(1),
                  3: FlexColumnWidth(1.5),
                  4: FlexColumnWidth(1.5),
                  5: FlexColumnWidth(1),
                  6: FlexColumnWidth(1),
                  7: FlexColumnWidth(0.8),
                },
          border: TableBorder(
            horizontalInside: BorderSide(color: colorScheme.outlineVariant),
            verticalInside: BorderSide(color: colorScheme.outlineVariant),
            left: BorderSide(color: colorScheme.outlineVariant),
            right: BorderSide(color: colorScheme.outlineVariant),
            top: BorderSide(color: colorScheme.outlineVariant),
            bottom: BorderSide(color: colorScheme.outlineVariant),
          ),
          children: [
            TableRow(
              decoration:
                  BoxDecoration(color: colorScheme.surfaceContainerHighest),
              children: [
                _cohortSummaryTableCell(colorScheme, '#', isHeader: true),
                _cohortSummaryTableCell(colorScheme, 'Year / Mode', isHeader: true),
                _cohortSummaryTableCell(colorScheme, 'Students', isHeader: true),
                _cohortSummaryTableCell(colorScheme, 'Attendance %', isHeader: true),
                _cohortSummaryTableCell(colorScheme, 'Outstanding Tests', isHeader: true),
                _cohortSummaryTableCell(colorScheme, 'Failed Tests', isHeader: true),
                _cohortSummaryTableCell(colorScheme, 'Passed Tests', isHeader: true),
                if (canShowBalance) _cohortSummaryTableCell(colorScheme, 'Balance due as expected monthly', isHeader: true),
                _cohortSummaryTableCell(colorScheme, 'View', isHeader: true),
              ],
            ),
            ...summaries.asMap().entries.map(
                  (entry) => TableRow(
                    children: [
                      MouseRegion(
                        onEnter: (_) => onRowHoverEnter?.call(entry.key),
                        onExit: (_) => onRowHoverExit?.call(entry.key),
                        child: _cohortSummaryTableCell(
                          colorScheme,
                          '${entry.key + 1}',
                          isHeader: false,
                          backgroundColor: hoveredRowIndex == entry.key
                              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                              : null,
                        ),
                      ),
                      MouseRegion(
                        onEnter: (_) => onRowHoverEnter?.call(entry.key),
                        onExit: (_) => onRowHoverExit?.call(entry.key),
                        child: _cohortSummaryTableCell(
                          colorScheme,
                          entry.value.cohortLabel,
                          isHeader: false,
                          backgroundColor: hoveredRowIndex == entry.key
                              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                              : null,
                        ),
                      ),
                      MouseRegion(
                        onEnter: (_) => onRowHoverEnter?.call(entry.key),
                        onExit: (_) => onRowHoverExit?.call(entry.key),
                        child: _cohortSummaryTableCell(
                          colorScheme,
                          '${entry.value.studentCount}',
                          isHeader: false,
                          backgroundColor: hoveredRowIndex == entry.key
                              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                              : null,
                        ),
                      ),
                      MouseRegion(
                        onEnter: (_) => onRowHoverEnter?.call(entry.key),
                        onExit: (_) => onRowHoverExit?.call(entry.key),
                        child: _cohortSummaryTableCell(
                          colorScheme,
                          entry.value.avgAttendancePercent != null
                              ? '${entry.value.avgAttendancePercent!.toStringAsFixed(1)}%'
                              : '—',
                          isHeader: false,
                          backgroundColor: hoveredRowIndex == entry.key
                              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                              : null,
                        ),
                      ),
                      MouseRegion(
                        onEnter: (_) => onRowHoverEnter?.call(entry.key),
                        onExit: (_) => onRowHoverExit?.call(entry.key),
                        child: _cohortSummaryTableCell(
                          colorScheme,
                          '${entry.value.outstandingTests}',
                          isHeader: false,
                          backgroundColor: hoveredRowIndex == entry.key
                              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                              : null,
                        ),
                      ),
                      MouseRegion(
                        onEnter: (_) => onRowHoverEnter?.call(entry.key),
                        onExit: (_) => onRowHoverExit?.call(entry.key),
                        child: _cohortSummaryTableCell(
                          colorScheme,
                          '${entry.value.failedTests}',
                          isHeader: false,
                          backgroundColor: hoveredRowIndex == entry.key
                              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                              : null,
                        ),
                      ),
                      MouseRegion(
                        onEnter: (_) => onRowHoverEnter?.call(entry.key),
                        onExit: (_) => onRowHoverExit?.call(entry.key),
                        child: _cohortSummaryTableCell(
                          colorScheme,
                          '${entry.value.passedTests}',
                          isHeader: false,
                          backgroundColor: hoveredRowIndex == entry.key
                              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                              : null,
                        ),
                      ),
                      if (canShowBalance)
                        MouseRegion(
                          onEnter: (_) => onRowHoverEnter?.call(entry.key),
                          onExit: (_) => onRowHoverExit?.call(entry.key),
                          child: _cohortSummaryTableCell(
                            colorScheme,
                            CurrencyUtils.formatRand(entry.value.balanceDueExpectedMonthly),
                            isHeader: false,
                            backgroundColor: hoveredRowIndex == entry.key
                                ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                                : null,
                          ),
                        ),
                      MouseRegion(
                        onEnter: (_) => onRowHoverEnter?.call(entry.key),
                        onExit: (_) => onRowHoverExit?.call(entry.key),
                        child: Container(
                          color: hoveredRowIndex == entry.key
                              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                              : null,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: TextButton(
                            onPressed: entry.value.studentCount == 0
                                ? null
                                : () => onViewCohort?.call(entry.value.year, entry.value.mode),
                            style: TextButton.styleFrom(
                              foregroundColor: redColor,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('View'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      );
    },
    loading: () => Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Center(
        child: CircularProgressIndicator(color: redColor),
      ),
    ),
    error: (error, _) => Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Center(
        child: Text(
          'Unable to load summary.',
          style: TextStyle(
            color: colorScheme.error,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
      ),
    ),
  );
}

/// Dashboard home screen: overview, stat cards, recent activities placeholder, quick links.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  late final ExpansibleController _keyStatsController;

  @override
  void initState() {
    super.initState();
    _keyStatsController = ExpansibleController();
  }

  @override
  void dispose() {
    _keyStatsController.dispose();
    super.dispose();
  }

  void _syncKeyStatsToTab(int index) {
    if (index == 0) {
      _keyStatsController.expand();
    } else {
      _keyStatsController.collapse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final redColor =
        themeMode == ThemeMode.dark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final auth = ref.watch(authStateProvider).valueOrNull;
    final displayName = auth is Authenticated ? auth.user.displayName : 'User';
    final studentsAsync = ref.watch(studentsStreamProvider('Active'));
    final outstandingAsync = ref.watch(dashboardOutstandingTestsProvider);
    final attendanceAsync = ref.watch(averageAttendancePercentageProvider);
    final balanceAsync = ref.watch(totalBalanceDueProvider);
    final cohortSummaryAsync = ref.watch(dashboardCohortSummaryProvider);
    final activitiesAsync = ref.watch(recentActivitiesEnrichedProvider);

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Dashboard Overview',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 24,
                      fontFamily: 'Questrial',
                    ),
                  ),
                ),
                RoleGuard(
                  canShow: RolePermissions.canExportReports,
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/reports?type=cohort-summary'),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Export'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Welcome to Charis Student Care, $displayName. This dashboard provides a concise summary of key student statistics and recent activities.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 24),
            _buildStatCardsSection(
              context,
              colorScheme,
              redColor,
              studentsAsync,
              outstandingAsync,
              attendanceAsync,
              balanceAsync,
              keyStatsController: _keyStatsController,
              canShowBalance: auth is Authenticated && RolePermissions.canManageFinancials(auth.role),
            ),
            const SizedBox(height: 24),
            Text(
              'Summary',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 12),
            _DashboardSummarySection(
              colorScheme: colorScheme,
              redColor: redColor,
              cohortSummaryAsync: cohortSummaryAsync,
              canShowBalance: auth is Authenticated && RolePermissions.canManageFinancials(auth.role),
              onTabIndexChanged: _syncKeyStatsToTab,
            ),
            const SizedBox(height: 24),
            _buildRecentActivitiesSection(
              context,
              colorScheme,
              redColor,
              activitiesAsync,
            ),
            const SizedBox(height: 24),
            Text(
              'Quick Links',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 12),
            _buildQuickLinks(context, colorScheme, redColor),
          ],
        ),
      ),
    );
  }

  /// Collapsible row of overview stat cards (Total Students, Attendance %, Outstanding Tests).
  Widget _buildStatCardsSection(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    AsyncValue<List<dynamic>> studentsAsync,
    AsyncValue<int> outstandingAsync,
    AsyncValue<double?> attendanceAsync,
    AsyncValue<double> balanceAsync, {
    required ExpansibleController keyStatsController,
    bool canShowBalance = true,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        controller: keyStatsController,
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        expandedAlignment: Alignment.centerLeft,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            'Key statistics',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 18,
              fontFamily: 'Questrial',
            ),
          ),
        ),
        controlAffinity: ListTileControlAffinity.trailing,
        children: [
          _buildStatCards(
            context,
            colorScheme,
            redColor,
            studentsAsync,
            outstandingAsync,
            attendanceAsync,
            balanceAsync,
            canShowBalance: canShowBalance,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCards(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    AsyncValue<List<dynamic>> studentsAsync,
    AsyncValue<int> outstandingAsync,
    AsyncValue<double?> attendanceAsync,
    AsyncValue<double> balanceAsync, {
    bool canShowBalance = true,
  }) {
    final totalStudents = studentsAsync.when(
      data: (list) => list.length,
      loading: () => null,
      error: (_, __) => null,
    );
    final outstandingTests = outstandingAsync.when(
      data: (count) => count,
      loading: () => null,
      error: (_, __) => null,
    );
    final attendancePercent = attendanceAsync.when(
      data: (percent) => percent,
      loading: () => null,
      error: (_, __) => null,
    );
    final totalBalance = balanceAsync.when(
      data: (amount) => amount,
      loading: () => null,
      error: (_, __) => null,
    );
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _statCard(
          colorScheme: colorScheme,
          title: 'Total Students',
          value: totalStudents != null ? '$totalStudents' : '—',
          subtitle: 'Currently enrolled',
          valueColor: redColor,
        ),
        _statCard(
          colorScheme: colorScheme,
          title: 'Attendance %',
          value: attendancePercent != null
              ? '${attendancePercent.toStringAsFixed(1)}%'
              : '—',
          subtitle: 'All recorded',
          valueColor: colorScheme.onSurface,
        ),
        _statCard(
          colorScheme: colorScheme,
          title: 'Outstanding Tests',
          value: outstandingTests != null ? '$outstandingTests' : '—',
          subtitle: 'Requires attention',
          valueColor: colorScheme.onSurface,
        ),
        if (canShowBalance)
          _statCard(
            colorScheme: colorScheme,
            title: 'Total Balance Due',
            value: totalBalance != null
                ? CurrencyUtils.formatRand(totalBalance)
                : '—',
            subtitle: 'Session outstanding',
            valueColor: colorScheme.onSurface,
            width: 280,
          ),
      ],
    );
  }

  Widget _statCard({
    required ColorScheme colorScheme,
    required String title,
    required String value,
    required String subtitle,
    required Color valueColor,
    double width = 200,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w700,
              fontSize: 28,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontFamily: 'Questrial',
            ),
          ),
        ],
      ),
    );
  }

  /// Collapsible Recent Activities section (collapsed by default to give more room for Summary).
  Widget _buildRecentActivitiesSection(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    AsyncValue<List<DashboardActivity>> activitiesAsync,
  ) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          'Recent Activities',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 18,
            fontFamily: 'Questrial',
          ),
        ),
        controlAffinity: ListTileControlAffinity.trailing,
        children: [
          _buildRecentActivities(
            context,
            colorScheme,
            redColor,
            activitiesAsync,
          ),
        ],
      ),
    );
  }

  Widget _buildRecentActivities(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    AsyncValue<List<DashboardActivity>> activitiesAsync,
  ) {
    return activitiesAsync.when(
      data: (activities) {
        if (activities.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Center(
              child: Text(
                'No recent activities to display. Please check back later.',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
            ),
          );
        }

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: activities.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: colorScheme.outlineVariant,
            ),
            itemBuilder: (context, index) {
              final activity = activities[index];
              final dateFormat = DateFormat('MMM d, y • h:mm a');
              final formattedDate = dateFormat.format(activity.timestamp);
              final activityTitle =
                  _getActivityTitle(activity.table, activity.operation);
              final rawUser =
                  activity.userDisplayName ?? activity.changeSet.userId;
              final userLabel =
                  rawUser.trim().isEmpty ? 'Unknown user' : rawUser;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      _getActivityIcon(activity.operation),
                      size: 20,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activityTitle,
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'Questrial',
                            ),
                          ),
                          if (activity.studentDisplay != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              activity.studentDisplay!,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontFamily: 'Questrial',
                              ),
                            ),
                          ],
                          const SizedBox(height: 2),
                          Text(
                            'By: $userLabel',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontFamily: 'Questrial',
                            ),
                          ),
                          if (activity.screen != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Screen: ${activity.screen}',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontFamily: 'Questrial',
                              ),
                            ),
                          ],
                          if (activity.whatChanged != null &&
                              activity.whatChanged!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Changes: ${activity.whatChanged}',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontFamily: 'Questrial',
                              ),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontFamily: 'Questrial',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Center(
          child: CircularProgressIndicator(
            color: redColor,
          ),
        ),
      ),
      error: (error, stack) => Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Center(
          child: Text(
            'Unable to load recent activities.',
            style: TextStyle(
              color: colorScheme.error,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
          ),
        ),
      ),
    );
  }

  /// Human-readable title from table and operation (e.g. "Updated student", "Added attendance").
  String _getActivityTitle(String table, String operation) {
    final singular = _tableSingularLabel(table);
    switch (operation) {
      case 'INSERT':
        return 'Added $singular';
      case 'UPDATE':
        return 'Updated $singular';
      case 'STATUS_CHANGE':
        return 'Changed $singular status';
      case 'DELETE':
        return 'Deleted $singular';
      default:
        return 'Modified $singular';
    }
  }

  String _tableSingularLabel(String table) {
    switch (table) {
      case 'students':
        return 'student';
      case 'attendance':
        return 'attendance';
      case 'tests':
        return 'test';
      case 'payments':
        return 'payment';
      case 'subjects':
        return 'subject';
      case 'missions':
        return 'mission';
      default:
        return table;
    }
  }

  IconData _getActivityIcon(String operation) {
    switch (operation) {
      case 'INSERT':
        return Icons.add_circle_outline;
      case 'UPDATE':
        return Icons.edit_outlined;
      case 'STATUS_CHANGE':
        return Icons.swap_horiz;
      case 'DELETE':
        return Icons.delete_outline;
      default:
        return Icons.info_outline;
    }
  }

  Widget _buildQuickLinks(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
  ) {
    return Row(
      children: [
        ElevatedButton(
          onPressed: () => context.go('/students'),
          style: ElevatedButton.styleFrom(
            backgroundColor: redColor,
            foregroundColor: AppColors.charisWhite,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('View All Students'),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: () => context.go('/reports'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.onSurfaceVariant,
            side: BorderSide(color: colorScheme.outlineVariant),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Generate Report'),
        ),
        const SizedBox(width: 12),
        RoleGuard(
          canShow: RolePermissions.canManageFinancials,
          child: OutlinedButton(
            onPressed: () => context.go('/payments'),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.onSurfaceVariant,
              side: BorderSide(color: colorScheme.outlineVariant),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Add New Finance Record'),
          ),
        ),
      ],
    );
  }
}

/// Class summary tab viewport height; Individual tab uses +120 (see [_kDashboardIndividualSummaryTabViewHeight]).
const double _kDashboardClassSummaryTabViewHeight = 380;

/// Individual summary tab: extra vertical space for the student table vs Class tab.
const double _kDashboardIndividualSummaryTabViewHeight =
    _kDashboardClassSummaryTabViewHeight + 120;

/// Summary section: TabBar (Individual / Class) and TabBarView with shared [TabController]
/// and pending cohort state so "View" on Class tab switches to Individual and filters by cohort.
class _DashboardSummarySection extends StatefulWidget {
  const _DashboardSummarySection({
    required this.colorScheme,
    required this.redColor,
    required this.cohortSummaryAsync,
    required this.canShowBalance,
    this.onTabIndexChanged,
  });

  final ColorScheme colorScheme;
  final Color redColor;
  final AsyncValue<List<DashboardCohortSummary>> cohortSummaryAsync;
  final bool canShowBalance;
  final ValueChanged<int>? onTabIndexChanged;

  @override
  State<_DashboardSummarySection> createState() =>
      _DashboardSummarySectionState();
}

class _DashboardSummarySectionState extends State<_DashboardSummarySection>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  String? _pendingCohortYear;
  String? _pendingCohortMode;
  int? _hoveredClassRowIndex;
  int _classHoverEpoch = 0;
  /// Drives [TabBarView] height: Individual tab (index 1) is taller than Class (0).
  bool _summaryShowsIndividualTab = false;

  @override
  void initState() {
    super.initState();
    // Class tab is index 0 and is the default view when dashboard loads.
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _tabController.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    if (!mounted) return;
    widget.onTabIndexChanged?.call(_tabController.index);
    final isIndividual = _tabController.index == 1;
    if (isIndividual != _summaryShowsIndividualTab) {
      setState(() => _summaryShowsIndividualTab = isIndividual);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    super.dispose();
  }

  void _onViewCohort(String year, String mode) {
    setState(() {
      _pendingCohortYear = year;
      _pendingCohortMode = mode;
    });
    _tabController.animateTo(1); // Individual tab is now at index 1
  }

  void _onClassRowHoverEnter(int rowIndex) {
    _classHoverEpoch++;
    if (_hoveredClassRowIndex == rowIndex) return;
    setState(() => _hoveredClassRowIndex = rowIndex);
  }

  void _onClassRowHoverExit(int rowIndex) {
    final localEpoch = _classHoverEpoch;
    Future<void>.delayed(const Duration(milliseconds: 20), () {
      if (!mounted) return;
      if (_classHoverEpoch != localEpoch) return;
      if (_hoveredClassRowIndex == rowIndex) {
        setState(() => _hoveredClassRowIndex = null);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final redColor = widget.redColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          labelColor: redColor,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          indicatorColor: redColor,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
          tabs: const [
            Tab(text: 'Class'),
            Tab(text: 'Individual'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: _summaryShowsIndividualTab
              ? _kDashboardIndividualSummaryTabViewHeight
              : _kDashboardClassSummaryTabViewHeight,
          child: TabBarView(
            controller: _tabController,
            children: [
              SingleChildScrollView(
                child: _buildSummaryTable(
                  context,
                  colorScheme,
                  redColor,
                  widget.cohortSummaryAsync,
                  _onViewCohort,
                  canShowBalance: widget.canShowBalance,
                  hoveredRowIndex: _hoveredClassRowIndex,
                  onRowHoverEnter: _onClassRowHoverEnter,
                  onRowHoverExit: _onClassRowHoverExit,
                ),
              ),
              _DashboardIndividualSummaryTab(
                colorScheme: colorScheme,
                redColor: redColor,
                canShowBalance: widget.canShowBalance,
                initialCohortYear: _pendingCohortYear,
                initialCohortMode: _pendingCohortMode,
                onAppliedInitialCohort: () {
                  setState(() {
                    _pendingCohortYear = null;
                    _pendingCohortMode = null;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Individual tab content: search, Year/Mode filters, and table with Summary column.
class _DashboardIndividualSummaryTab extends ConsumerStatefulWidget {
  const _DashboardIndividualSummaryTab({
    required this.colorScheme,
    required this.redColor,
    required this.canShowBalance,
    this.initialCohortYear,
    this.initialCohortMode,
    this.onAppliedInitialCohort,
  });

  final ColorScheme colorScheme;
  final Color redColor;
  final bool canShowBalance;
  final String? initialCohortYear;
  final String? initialCohortMode;
  final VoidCallback? onAppliedInitialCohort;

  @override
  ConsumerState<_DashboardIndividualSummaryTab> createState() =>
      _DashboardIndividualSummaryTabState();
}

/// Minimum width for the Individual table so it can scroll horizontally when the window is narrow.
const double _kIndividualTableMinWidth = 900;

class _DashboardIndividualSummaryTabState
    extends ConsumerState<_DashboardIndividualSummaryTab> {
  String _searchQuery = '';
  String? _yearFilter;
  String? _modeFilter;
  String? _statusFilter = 'Active';
  bool _appliedInitialCohort = false;
  final ScrollController _horizontalScrollController = ScrollController();
  int? _hoveredIndividualRowIndex;
  int _individualHoverEpoch = 0;

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  void _onIndividualRowHoverEnter(int rowIndex) {
    _individualHoverEpoch++;
    if (_hoveredIndividualRowIndex == rowIndex) return;
    setState(() => _hoveredIndividualRowIndex = rowIndex);
  }

  void _onIndividualRowHoverExit(int rowIndex) {
    final localEpoch = _individualHoverEpoch;
    Future<void>.delayed(const Duration(milliseconds: 20), () {
      if (!mounted) return;
      if (_individualHoverEpoch != localEpoch) return;
      if (_hoveredIndividualRowIndex == rowIndex) {
        setState(() => _hoveredIndividualRowIndex = null);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _DashboardIndividualSummaryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialCohortYear == null && widget.initialCohortMode == null) {
      _appliedInitialCohort = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.initialCohortYear != null &&
        widget.initialCohortMode != null &&
        !_appliedInitialCohort) {
      _appliedInitialCohort = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _yearFilter = widget.initialCohortYear;
          _modeFilter = widget.initialCohortMode;
        });
        widget.onAppliedInitialCohort?.call();
      });
    }

    final modeOptions = ref.watch(modeOptionsForCurrentUserProvider);
    if (modeOptions.length == 1 && _modeFilter != modeOptions[0]) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _modeFilter = modeOptions[0]);
      });
    }

    final summaryAsync =
        ref.watch(dashboardStudentSummaryProvider(_statusFilter));
    final studentsAsync = ref.watch(studentsStreamProvider(_statusFilter));

    return summaryAsync.when(
      data: (summaries) {
        final students = studentsAsync.valueOrNull ?? [];
        final studentMap = {for (final s in students) s.id: s};
        var filtered = summaries;
        final query = _searchQuery.trim();
        if (query.isNotEmpty) {
          final lower = query.toLowerCase();
          filtered = filtered
              .where((s) => s.displayName.toLowerCase().contains(lower))
              .toList();
        }
        if (_yearFilter != null) {
          filtered = filtered.where((s) => s.year == _yearFilter).toList();
        }
        if (_modeFilter != null) {
          filtered = filtered.where((s) => s.mode == _modeFilter).toList();
        }

        return SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFilterRow(),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth.isFinite &&
                          constraints.maxWidth >= _kIndividualTableMinWidth
                      ? constraints.maxWidth
                      : _kIndividualTableMinWidth;
                  return Scrollbar(
                    controller: _horizontalScrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      controller: _horizontalScrollController,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: width,
                          maxWidth: width,
                        ),
                        child: _buildTable(
                          context,
                          filtered,
                          studentMap,
                          true, // Ministry Hours column always visible
                          widget.canShowBalance,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: widget.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.colorScheme.outlineVariant),
        ),
        child: Center(
          child: CircularProgressIndicator(color: widget.redColor),
        ),
      ),
      error: (error, _) => Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: widget.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: widget.colorScheme.outlineVariant),
        ),
        child: Center(
          child: Text(
            'Unable to load summary.',
            style: TextStyle(
              color: widget.colorScheme.error,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildClassDropdown(ColorScheme colorScheme) {
    final classes = ref.watch(classesVisibleToCurrentUserProvider).valueOrNull ?? [];
    return DropdownButton<String?>(
      value: _yearFilter,
      focusColor: Colors.transparent,
      hint: Text(
        'Class',
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
      ),
      isExpanded: true,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      items: [
        DropdownMenuItem<String?>(
          value: null,
          child: Text(
            'All',
            style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
          ),
        ),
        ...classes.map<DropdownMenuItem<String?>>(
          (SchoolClass c) => DropdownMenuItem<String?>(
            value: c.name,
            child: Text(
              c.name,
              style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
            ),
          ),
        ),
      ],
      onChanged: (v) => setState(() => _yearFilter = v),
    );
  }

  Widget _buildModeFilterWidget(ColorScheme colorScheme) {
    final modeOptions = ref.watch(modeOptionsForCurrentUserProvider);
    if (modeOptions.length == 1) {
      return SizedBox(
        width: 120,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outlineVariant),
          ),
          child: Text(
            modeOptions[0],
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: 120,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: DropdownButton<String?>(
          value: _modeFilter,
          hint: Text(
            'Mode',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
          isExpanded: true,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(8),
          items: [
            DropdownMenuItem<String?>(
              value: null,
              child: Text(
                'All',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                ),
              ),
            ),
            ...modeOptions.map(
              (v) => DropdownMenuItem<String?>(
                value: v,
                child: Text(
                  v,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
          onChanged: (v) => setState(() => _modeFilter = v),
        ),
      ),
    );
  }

  Widget _buildFilterRow() {
    final colorScheme = widget.colorScheme;
    return Row(
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search students...',
              hintStyle:
                  TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
              prefixIcon: Icon(
                Icons.search,
                color: colorScheme.onSurfaceVariant,
                size: 22,
              ),
              filled: true,
              fillColor: Colors.transparent,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: _buildClassDropdown(colorScheme),
          ),
        ),
        const SizedBox(width: 12),
        _buildModeFilterWidget(colorScheme),
        const SizedBox(width: 12),
        SizedBox(
          width: 140,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: DropdownButton<String?>(
              value: _statusFilter,
              hint: Text(
                'Status',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              isExpanded: true,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(8),
              items: _individualStatusOptions
                  .map(
                    (v) => DropdownMenuItem<String?>(
                      value: v,
                      child: Text(
                        v ?? 'All',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() => _statusFilter = v),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTable(
    BuildContext context,
    List<DashboardStudentSummary> filtered,
    Map<int, Student> studentMap,
    bool showMinistryHours,
    bool showFinancialColumns,
  ) {
    final colorScheme = widget.colorScheme;
    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Center(
          child: Text(
            'No students match the filters.',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
          ),
        ),
      );
    }

    int col = 0;
    final columnWidths = <int, FlexColumnWidth>{
      col++: const FlexColumnWidth(0.6),
      col++: const FlexColumnWidth(2.5),
      col++: const FlexColumnWidth(1.5),
      col++: const FlexColumnWidth(1.2),
      col++: const FlexColumnWidth(1.2),
      col++: const FlexColumnWidth(1),
      col++: const FlexColumnWidth(1),
    };
    if (showFinancialColumns) {
      columnWidths[col++] = const FlexColumnWidth(1.5); // Balance due as expected monthly
    }
    if (showMinistryHours) {
      columnWidths[col++] = const FlexColumnWidth(2);
    }
    if (showFinancialColumns) {
      columnWidths[col++] = const FlexColumnWidth(1.2); // Mission Fund
    }
    columnWidths[col] = const FlexColumnWidth(1.4); // Summary

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
      ),
      child: Table(
        columnWidths: columnWidths,
        border: TableBorder(
          horizontalInside: BorderSide(color: colorScheme.outlineVariant),
          verticalInside: BorderSide(color: colorScheme.outlineVariant),
          left: BorderSide(color: colorScheme.outlineVariant),
          right: BorderSide(color: colorScheme.outlineVariant),
          top: BorderSide(color: colorScheme.outlineVariant),
          bottom: BorderSide(color: colorScheme.outlineVariant),
        ),
        children: [
          TableRow(
            decoration:
                BoxDecoration(color: colorScheme.surfaceContainerHighest),
            children: [
              _tableCell(colorScheme, '#', isHeader: true),
              _tableCell(colorScheme, 'Student', isHeader: true),
              _tableCell(colorScheme, 'Year / Mode', isHeader: true),
              _tableCell(colorScheme, 'Attendance %', isHeader: true),
              _tableCell(colorScheme, 'Outstanding Tests', isHeader: true),
              _tableCell(colorScheme, 'Failed Tests', isHeader: true),
              _tableCell(colorScheme, 'Passed Tests', isHeader: true),
              if (showFinancialColumns)
                _tableCell(colorScheme, 'Balance due as expected monthly', isHeader: true),
              if (showMinistryHours)
                _tableCell(colorScheme, 'Ministry Hours', isHeader: true),
              if (showFinancialColumns)
                _tableCell(colorScheme, 'Mission Fund', isHeader: true),
              _tableCell(colorScheme, 'Summary', isHeader: true),
            ],
          ),
          ...filtered.asMap().entries.map((entry) {
            final index = entry.key;
            final s = entry.value;
            final student = studentMap[s.studentId];
            return TableRow(
              children: [
                MouseRegion(
                  onEnter: (_) => _onIndividualRowHoverEnter(index),
                  onExit: (_) => _onIndividualRowHoverExit(index),
                  child: _tableCell(
                    colorScheme,
                    '${index + 1}',
                    isHeader: false,
                    backgroundColor: _hoveredIndividualRowIndex == index
                        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                        : null,
                  ),
                ),
                MouseRegion(
                  onEnter: (_) => _onIndividualRowHoverEnter(index),
                  onExit: (_) => _onIndividualRowHoverExit(index),
                  child: _tableCell(
                    colorScheme,
                    s.displayName,
                    isHeader: false,
                    backgroundColor: _hoveredIndividualRowIndex == index
                        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                        : null,
                  ),
                ),
                MouseRegion(
                  onEnter: (_) => _onIndividualRowHoverEnter(index),
                  onExit: (_) => _onIndividualRowHoverExit(index),
                  child: _tableCell(
                    colorScheme,
                    s.yearModeLabel,
                    isHeader: false,
                    backgroundColor: _hoveredIndividualRowIndex == index
                        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                        : null,
                  ),
                ),
                MouseRegion(
                  onEnter: (_) => _onIndividualRowHoverEnter(index),
                  onExit: (_) => _onIndividualRowHoverExit(index),
                  child: _tableCell(
                    colorScheme,
                    s.avgAttendancePercent != null
                        ? '${s.avgAttendancePercent!.toStringAsFixed(1)}%'
                        : '—',
                    isHeader: false,
                    backgroundColor: _hoveredIndividualRowIndex == index
                        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                        : null,
                  ),
                ),
                MouseRegion(
                  onEnter: (_) => _onIndividualRowHoverEnter(index),
                  onExit: (_) => _onIndividualRowHoverExit(index),
                  child: _tableCell(
                    colorScheme,
                    '${s.outstandingTests}',
                    isHeader: false,
                    backgroundColor: _hoveredIndividualRowIndex == index
                        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                        : null,
                  ),
                ),
                MouseRegion(
                  onEnter: (_) => _onIndividualRowHoverEnter(index),
                  onExit: (_) => _onIndividualRowHoverExit(index),
                  child: _tableCell(
                    colorScheme,
                    '${s.failedTests}',
                    isHeader: false,
                    backgroundColor: _hoveredIndividualRowIndex == index
                        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                        : null,
                  ),
                ),
                MouseRegion(
                  onEnter: (_) => _onIndividualRowHoverEnter(index),
                  onExit: (_) => _onIndividualRowHoverExit(index),
                  child: _tableCell(
                    colorScheme,
                    '${s.passedTests}',
                    isHeader: false,
                    backgroundColor: _hoveredIndividualRowIndex == index
                        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                        : null,
                  ),
                ),
                if (showFinancialColumns)
                  MouseRegion(
                    onEnter: (_) => _onIndividualRowHoverEnter(index),
                    onExit: (_) => _onIndividualRowHoverExit(index),
                    child: _tableCell(
                      colorScheme,
                      CurrencyUtils.formatRand(s.balanceDueExpectedMonthly),
                      isHeader: false,
                      backgroundColor: _hoveredIndividualRowIndex == index
                          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                          : null,
                    ),
                  ),
                if (showMinistryHours)
                  MouseRegion(
                    onEnter: (_) => _onIndividualRowHoverEnter(index),
                    onExit: (_) => _onIndividualRowHoverExit(index),
                    child: _tableCell(
                      colorScheme,
                      s.totalMinistryHours.toStringAsFixed(1),
                      isHeader: false,
                      backgroundColor: _hoveredIndividualRowIndex == index
                          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                          : null,
                    ),
                  ),
                if (showFinancialColumns)
                  MouseRegion(
                    onEnter: (_) => _onIndividualRowHoverEnter(index),
                    onExit: (_) => _onIndividualRowHoverExit(index),
                    child: _tableCell(
                      colorScheme,
                      CurrencyUtils.formatRand(s.missionFund),
                      isHeader: false,
                      backgroundColor: _hoveredIndividualRowIndex == index
                          ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                          : null,
                    ),
                  ),
                MouseRegion(
                  onEnter: (_) => _onIndividualRowHoverEnter(index),
                  onExit: (_) => _onIndividualRowHoverExit(index),
                  child: Container(
                    color: _hoveredIndividualRowIndex == index
                        ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
                        : null,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: student != null
                        ? TextButton(
                            onPressed: () {
                              StudentSummaryDialog.show(
                                context: context,
                                student: student,
                              );
                            },
                            style: TextButton.styleFrom(
                              foregroundColor: widget.redColor,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('View'),
                          )
                        : Tooltip(
                            message: 'Student not found',
                            child: TextButton(
                              onPressed: null,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: Text(
                                'View',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _tableCell(
    ColorScheme colorScheme,
    String text, {
    required bool isHeader,
    Color? backgroundColor,
  }) {
    return Container(
      color: backgroundColor,
      padding: AppTableStyle.cellPadding,
      child: Text(
        text,
        style: isHeader
            ? AppTableStyle.headerTextStyle(colorScheme)
            : AppTableStyle.bodyTextStyle(colorScheme).copyWith(color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
