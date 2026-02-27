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
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/test_providers.dart';
import 'package:charis_student_care/presentation/providers/settings_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/widgets/student_summary_dialog.dart';

/// Mode options for Individual tab filter (Full-time, Hybrid).
const List<String> _individualModeOptions = ['Full-time', 'Hybrid'];

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
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Text(
      text,
      style: TextStyle(
        color:
            isHeader ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
        fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
        fontSize: 14,
        fontFamily: 'Questrial',
      ),
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
  void Function(String year, String mode)? onViewCohort,
) {
  return cohortSummaryAsync.when(
    data: (summaries) {
      if (summaries.isEmpty) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
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
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Table(
          columnWidths: const {
            0: FlexColumnWidth(0.6),
            1: FlexColumnWidth(2),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1.5),
            4: FlexColumnWidth(1.5),
            5: FlexColumnWidth(1),
            6: FlexColumnWidth(1),
            7: FlexColumnWidth(2),
            8: FlexColumnWidth(0.8),
          },
          border: TableBorder(
            horizontalInside: BorderSide(color: colorScheme.outlineVariant),
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
                _cohortSummaryTableCell(colorScheme, 'Avg Attendance %', isHeader: true),
                _cohortSummaryTableCell(colorScheme, 'Outstanding Tests', isHeader: true),
                _cohortSummaryTableCell(colorScheme, 'Failed Tests', isHeader: true),
                _cohortSummaryTableCell(colorScheme, 'Passed Tests', isHeader: true),
                _cohortSummaryTableCell(colorScheme, 'Total Balance', isHeader: true),
                _cohortSummaryTableCell(colorScheme, 'View', isHeader: true),
              ],
            ),
            ...summaries.asMap().entries.map(
                  (entry) => TableRow(
                    children: [
                      _cohortSummaryTableCell(
                        colorScheme,
                        '${entry.key + 1}',
                        isHeader: false,
                      ),
                      _cohortSummaryTableCell(
                        colorScheme,
                        entry.value.cohortLabel,
                        isHeader: false,
                      ),
                      _cohortSummaryTableCell(
                        colorScheme,
                        '${entry.value.studentCount}',
                        isHeader: false,
                      ),
                      _cohortSummaryTableCell(
                        colorScheme,
                        entry.value.avgAttendancePercent != null
                            ? '${entry.value.avgAttendancePercent!.toStringAsFixed(1)}%'
                            : '—',
                        isHeader: false,
                      ),
                      _cohortSummaryTableCell(
                        colorScheme,
                        '${entry.value.outstandingTests}',
                        isHeader: false,
                      ),
                      _cohortSummaryTableCell(
                        colorScheme,
                        '${entry.value.failedTests}',
                        isHeader: false,
                      ),
                      _cohortSummaryTableCell(
                        colorScheme,
                        '${entry.value.passedTests}',
                        isHeader: false,
                      ),
                      _cohortSummaryTableCell(
                        colorScheme,
                        CurrencyUtils.formatRand(entry.value.totalBalance),
                        isHeader: false,
                      ),
                      Padding(
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
        borderRadius: BorderRadius.circular(12),
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
        borderRadius: BorderRadius.circular(12),
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
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final auth = ref.watch(authStateProvider).valueOrNull;
    final displayName = auth is Authenticated ? auth.user.displayName : 'User';
    final studentsAsync = ref.watch(studentsStreamProvider('Active'));
    final outstandingAsync = ref.watch(totalOutstandingCountProvider);
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
            _buildStatCards(
              context,
              colorScheme,
              redColor,
              studentsAsync,
              outstandingAsync,
              attendanceAsync,
              balanceAsync,
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

  Widget _buildStatCards(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    AsyncValue<List<dynamic>> studentsAsync,
    AsyncValue<int> outstandingAsync,
    AsyncValue<double?> attendanceAsync,
    AsyncValue<double> balanceAsync,
  ) {
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
      data: (balance) => balance,
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
          title: 'Avg Attendance %',
          value: attendancePercent != null
              ? '${attendancePercent.toStringAsFixed(1)}%'
              : '—',
          subtitle: 'Last 30 days',
          valueColor: colorScheme.onSurface,
        ),
        _statCard(
          colorScheme: colorScheme,
          title: 'Outstanding Tests',
          value: outstandingTests != null ? '$outstandingTests' : '—',
          subtitle: 'Requires attention',
          valueColor: colorScheme.onSurface,
        ),
        _statCard(
          colorScheme: colorScheme,
          title: 'Total Balance Due',
          value: totalBalance != null
              ? CurrencyUtils.formatRand(totalBalance)
              : '—',
          subtitle: 'Across all students',
          valueColor: redColor,
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
            side: BorderSide(color: colorScheme.outline),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Generate Report'),
        ),
        const SizedBox(width: 12),
        OutlinedButton(
          onPressed: () => context.go('/payments'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.onSurfaceVariant,
            side: BorderSide(color: colorScheme.outline),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Add New Payment'),
        ),
      ],
    );
  }
}

/// Summary section: TabBar (Individual / Class) and TabBarView with shared [TabController]
/// and pending cohort state so "View" on Class tab switches to Individual and filters by cohort.
class _DashboardSummarySection extends StatefulWidget {
  const _DashboardSummarySection({
    required this.colorScheme,
    required this.redColor,
    required this.cohortSummaryAsync,
  });

  final ColorScheme colorScheme;
  final Color redColor;
  final AsyncValue<List<DashboardCohortSummary>> cohortSummaryAsync;

  @override
  State<_DashboardSummarySection> createState() =>
      _DashboardSummarySectionState();
}

class _DashboardSummarySectionState extends State<_DashboardSummarySection>
    with TickerProviderStateMixin {
  late final TabController _tabController;
  String? _pendingCohortYear;
  String? _pendingCohortMode;

  @override
  void initState() {
    super.initState();
    // Class tab is index 0 and is the default view when dashboard loads.
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
  }

  @override
  void dispose() {
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
          height: 380,
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
                ),
              ),
              _DashboardIndividualSummaryTab(
                colorScheme: colorScheme,
                redColor: redColor,
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
    this.initialCohortYear,
    this.initialCohortMode,
    this.onAppliedInitialCohort,
  });

  final ColorScheme colorScheme;
  final Color redColor;
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
  String? _modeFilter = 'Full-time';
  String? _statusFilter = 'Active';
  bool _appliedInitialCohort = false;
  bool _appliedDefaultYearFilter = false;
  bool _defaultYearScheduled = false;
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
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

    final auth = ref.watch(authStateProvider).valueOrNull;
    final visibleClasses = ref.watch(classesVisibleToCurrentUserProvider).valueOrNull;
    if (auth is Authenticated &&
        visibleClasses != null &&
        !_appliedDefaultYearFilter &&
        !_defaultYearScheduled &&
        _yearFilter == null &&
        widget.initialCohortYear == null) {
      _defaultYearScheduled = true;
      final role = auth.role;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _appliedDefaultYearFilter = true;
          _yearFilter = role == UserRole.facilitator
              ? (visibleClasses.isNotEmpty ? visibleClasses.first.name : null)
              : 'Year 1';
        });
      });
    }

    final summaryAsync =
        ref.watch(dashboardStudentSummaryProvider(_statusFilter));
    final studentsAsync = ref.watch(studentsStreamProvider(_statusFilter));
    final showMinistryHours =
        ref.watch(dashboardShowMinistryHoursProvider).valueOrNull ?? false;

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
              _buildFilterRow(showMinistryHours),
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
                          showMinistryHours,
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
      hint: Text(
        'Class',
        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
      ),
      isExpanded: true,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      items: classes
          .map((c) => DropdownMenuItem<String?>(
                value: c.name,
                child: Text(c.name,
                    style: TextStyle(color: colorScheme.onSurface, fontSize: 14),),
              ),
            )
          .toList(),
      onChanged: (v) => setState(() => _yearFilter = v),
    );
  }

  Widget _buildFilterRow(bool showMinistryHours) {
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
              fillColor: colorScheme.surfaceContainerHighest,
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
        FilterChip(
          label: const Text('Show Ministry Hours'),
          selected: showMinistryHours,
          onSelected: (selected) {
            ref.read(dashboardShowMinistryHoursNotifierProvider).set(selected);
          },
          selectedColor: widget.redColor.withValues(alpha: 0.2),
          checkmarkColor: widget.redColor,
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outline),
            ),
            child: _buildClassDropdown(colorScheme),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 120,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outline),
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
              items: _individualModeOptions
                  .map(
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
                  )
                  .toList(),
              onChanged: (v) => setState(() => _modeFilter = v),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 140,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outline),
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
  ) {
    final colorScheme = widget.colorScheme;
    if (filtered.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
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

    final columnWidths = showMinistryHours
        ? const {
            0: FlexColumnWidth(0.6),
            1: FlexColumnWidth(2.5),
            2: FlexColumnWidth(1.5),
            3: FlexColumnWidth(1.2),
            4: FlexColumnWidth(1.2),
            5: FlexColumnWidth(1),
            6: FlexColumnWidth(1),
            7: FlexColumnWidth(1.5),
            8: FlexColumnWidth(2),
            9: FlexColumnWidth(1.2),
            10: FlexColumnWidth(1.4),
          }
        : const {
            0: FlexColumnWidth(0.6),
            1: FlexColumnWidth(2.5),
            2: FlexColumnWidth(1.5),
            3: FlexColumnWidth(1.2),
            4: FlexColumnWidth(1.2),
            5: FlexColumnWidth(1),
            6: FlexColumnWidth(1),
            7: FlexColumnWidth(1.5),
            8: FlexColumnWidth(1.2),
            9: FlexColumnWidth(1.4),
          };

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: columnWidths,
        border: TableBorder(
          horizontalInside: BorderSide(color: colorScheme.outlineVariant),
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
              _tableCell(colorScheme, 'Avg Attendance %', isHeader: true),
              _tableCell(colorScheme, 'Outstanding Tests', isHeader: true),
              _tableCell(colorScheme, 'Failed Tests', isHeader: true),
              _tableCell(colorScheme, 'Passed Tests', isHeader: true),
              _tableCell(colorScheme, 'Total Balance', isHeader: true),
              if (showMinistryHours)
                _tableCell(colorScheme, 'Ministry Hours', isHeader: true),
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
                _tableCell(colorScheme, '${index + 1}', isHeader: false),
                _tableCell(colorScheme, s.displayName, isHeader: false),
                _tableCell(colorScheme, s.yearModeLabel, isHeader: false),
                _tableCell(
                  colorScheme,
                  s.avgAttendancePercent != null
                      ? '${s.avgAttendancePercent!.toStringAsFixed(1)}%'
                      : '—',
                  isHeader: false,
                ),
                _tableCell(
                  colorScheme,
                  '${s.outstandingTests}',
                  isHeader: false,
                ),
                _tableCell(colorScheme, '${s.failedTests}', isHeader: false),
                _tableCell(colorScheme, '${s.passedTests}', isHeader: false),
                _tableCell(
                  colorScheme,
                  CurrencyUtils.formatRand(s.totalBalance),
                  isHeader: false,
                ),
                if (showMinistryHours)
                  _tableCell(
                    colorScheme,
                    s.totalMinistryHours > 0
                        ? s.totalMinistryHours.toStringAsFixed(1)
                        : '—',
                    isHeader: false,
                  ),
                _tableCell(
                  colorScheme,
                  s.missionFund > 0
                      ? CurrencyUtils.formatRand(s.missionFund)
                      : '—',
                  isHeader: false,
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              'View',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.5),
                                fontSize: 14,
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
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: TextStyle(
          color:
              isHeader ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
          fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
          fontSize: 14,
          fontFamily: 'Questrial',
        ),
      ),
    );
  }
}
