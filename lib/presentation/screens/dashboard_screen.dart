import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/core/utils/currency_utils.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/test_providers.dart';

/// Dashboard home screen: overview, stat cards, recent activities placeholder, quick links.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final auth = ref.watch(authStateProvider).valueOrNull;
    final displayName = auth is Authenticated ? auth.user.displayName : 'User';
    final studentsAsync = ref.watch(studentsStreamProvider('Active'));
    final outstandingAsync = ref.watch(totalOutstandingCountProvider);

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Dashboard Overview',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 24,
                fontFamily: 'Questrial',
              ),
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
            _buildStatCards(context, colorScheme, studentsAsync, outstandingAsync),
            const SizedBox(height: 24),
            Text(
              'Recent Activities',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 12),
            _buildRecentActivitiesPlaceholder(colorScheme),
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
            _buildQuickLinks(context, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCards(
    BuildContext context,
    ColorScheme colorScheme,
    AsyncValue<List<dynamic>> studentsAsync,
    AsyncValue<int> outstandingAsync,
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

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _statCard(
          colorScheme: colorScheme,
          title: 'Total Students',
          value: totalStudents != null ? '$totalStudents' : '—',
          subtitle: 'Currently enrolled',
          valueColor: AppColors.primaryActionRed,
        ),
        _statCard(
          colorScheme: colorScheme,
          title: 'Avg Attendance %',
          value: '92.5%',
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
          value: CurrencyUtils.formatRand(15300),
          subtitle: 'Across all students',
          valueColor: AppColors.primaryActionRed,
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
  }) {
    return Container(
      width: 200,
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

  Widget _buildRecentActivitiesPlaceholder(ColorScheme colorScheme) {
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

  Widget _buildQuickLinks(BuildContext context, ColorScheme colorScheme) {
    return Row(
      children: [
        ElevatedButton(
          onPressed: () => context.go('/students'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryActionRed,
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
