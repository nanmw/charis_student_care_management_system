import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/core/utils/currency_utils.dart';
import 'package:charis_student_care/core/utils/date_utils.dart' as app_date_utils;
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/student_summary_providers.dart';
import 'package:charis_student_care/presentation/providers/subject_providers.dart';
import 'package:charis_student_care/presentation/providers/test_providers.dart';
import 'package:charis_student_care/presentation/widgets/searchable_dropdown.dart';

/// Comprehensive student summary dialog showing all student information
class StudentSummaryDialog extends ConsumerStatefulWidget {
  const StudentSummaryDialog({super.key, required this.student});

  final Student student;

  static Future<void> show({
    required BuildContext context,
    required Student student,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => StudentSummaryDialog(student: student),
    );
  }

  @override
  ConsumerState<StudentSummaryDialog> createState() =>
      _StudentSummaryDialogState();
}

class _StudentSummaryDialogState extends ConsumerState<StudentSummaryDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;

    return Dialog(
      backgroundColor:
          isDark ? AppColors.surfaceDarkElevated : AppColors.charisWhite,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.student.surname}, ${widget.student.firstName}',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            fontFamily: 'Questrial',
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Student Summary',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 14,
                            fontFamily: 'Questrial',
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: colorScheme.onSurfaceVariant),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            // Tabs
            TabBar(
              controller: _tabController,
              isScrollable: true,
              labelColor: redColor,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorColor: redColor,
              tabs: const [
                Tab(text: 'Student'),
                Tab(text: 'Attendance'),
                Tab(text: 'Tests'),
                Tab(text: 'Payments'),
                Tab(text: 'Ministry'),
                Tab(text: 'Missions'),
              ],
            ),
            // Tab content
            Flexible(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildStudentTab(colorScheme, redColor),
                  _buildAttendanceTab(colorScheme),
                  _buildTestsTab(colorScheme),
                  _buildPaymentsTab(colorScheme),
                  _buildMinistryTab(colorScheme),
                  _buildMissionsTab(colorScheme),
                ],
              ),
            ),
            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colorScheme.onSurfaceVariant,
                  side: BorderSide(color: colorScheme.outline),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentTab(ColorScheme colorScheme, Color redColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row('Surname', widget.student.surname, colorScheme),
          _row('First names', widget.student.firstName, colorScheme),
          _row('Year', widget.student.year ?? '—', colorScheme),
          _row('Mode', widget.student.mode ?? '—', colorScheme),
          _row('Admission year', widget.student.admissionYear ?? '—', colorScheme),
          _row('Status', widget.student.status, colorScheme),
          _row('Phone', widget.student.contactInfo ?? '—', colorScheme),
          _row('Email', widget.student.email ?? '—', colorScheme),
          const SizedBox(height: 16),
          _checkboxRow('Handbook', widget.student.handbook, colorScheme, redColor),
          _checkboxRow('Media Release', widget.student.mediaRelease, colorScheme, redColor),
          _checkboxRow('Accident Waiver', widget.student.accidentWaiver, colorScheme, redColor),
        ],
      ),
    );
  }

  Widget _buildAttendanceTab(ColorScheme colorScheme) {
    final attendanceAsync =
        ref.watch(attendanceSummaryForStudentProvider(widget.student.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: attendanceAsync.when(
        data: (summary) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _statCard(
                'Total Days',
                summary.totalDays.toString(),
                colorScheme,
              ),
              const SizedBox(height: 16),
              _statCard(
                'Present Days',
                summary.presentDays.toString(),
                colorScheme,
              ),
              const SizedBox(height: 16),
              _statCard(
                'Attendance Percentage',
                '${summary.percentage.toStringAsFixed(1)}%',
                colorScheme,
                highlight: true,
              ),
              if (summary.recentDates.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Recent Attendance Dates',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    fontFamily: 'Questrial',
                  ),
                ),
                const SizedBox(height: 12),
                ...summary.recentDates.map((date) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.calendar_today,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            app_date_utils.DateUtils.formatDisplayDate(date),
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontSize: 14,
                              fontFamily: 'Questrial',
                            ),
                          ),
                        ],
                      ),
                    ),),
              ],
              if (summary.totalDays == 0)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No attendance records found',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontFamily: 'Questrial',
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(
            'Error loading attendance: $err',
            style: TextStyle(color: colorScheme.error, fontSize: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildTestsTab(ColorScheme colorScheme) {
    // Default to 'Year 1' if student year is not set (for subject lookup and outstanding count)
    final studentYear = widget.student.year ?? 'Year 1';
    final studentMode = widget.student.mode ?? 'Full-time';
    final testsAsync = ref.watch(
      testSummaryForStudentProvider((widget.student.id, studentYear, studentMode)),
    );
    final subjectsAsync = ref.watch(subjectsForYearStreamProvider(studentYear));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: testsAsync.when(
        data: (summary) {
          // Handle subjects loading/error states separately
          if (subjectsAsync.isLoading) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _statCard('Total Tests', summary.totalTests.toString(), colorScheme),
                const SizedBox(height: 16),
                _statCard(
                  'Outstanding Tests',
                  summary.outstandingTests.toString(),
                  colorScheme,
                  highlight: summary.outstandingTests > 0,
                ),
                const SizedBox(height: 16),
                _statCard(
                  'Passed Tests',
                  summary.passedTests.toString(),
                  colorScheme,
                ),
                const SizedBox(height: 16),
                _statCard(
                  'Average Score',
                  summary.averageScore.toStringAsFixed(1),
                  colorScheme,
                  highlight: true,
                ),
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            );
          }

          if (subjectsAsync.hasError) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _statCard('Total Tests', summary.totalTests.toString(), colorScheme),
                const SizedBox(height: 16),
                _statCard(
                  'Outstanding Tests',
                  summary.outstandingTests.toString(),
                  colorScheme,
                  highlight: summary.outstandingTests > 0,
                ),
                const SizedBox(height: 16),
                _statCard(
                  'Passed Tests',
                  summary.passedTests.toString(),
                  colorScheme,
                ),
                const SizedBox(height: 16),
                _statCard(
                  'Average Score',
                  summary.averageScore.toStringAsFixed(1),
                  colorScheme,
                  highlight: true,
                ),
                const SizedBox(height: 24),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Error loading subjects: ${subjectsAsync.error}',
                      style: TextStyle(color: colorScheme.error, fontSize: 14),
                    ),
                  ),
                ),
              ],
            );
          }

          final subjects = subjectsAsync.value ?? [];
          final subjectMap = {for (final s in subjects) s.id: s};

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _statCard('Total Tests', summary.totalTests.toString(), colorScheme),
              const SizedBox(height: 16),
              _statCard(
                'Outstanding Tests',
                summary.outstandingTests.toString(),
                colorScheme,
                highlight: summary.outstandingTests > 0,
              ),
              const SizedBox(height: 16),
              _statCard(
                'Passed Tests',
                summary.passedTests.toString(),
                colorScheme,
              ),
              const SizedBox(height: 16),
              _statCard(
                'Average Score',
                summary.averageScore.toStringAsFixed(1),
                colorScheme,
                highlight: true,
              ),
              if (summary.recentTests.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Recent Tests',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    fontFamily: 'Questrial',
                  ),
                ),
                const SizedBox(height: 12),
                ...summary.recentTests.map((test) {
                  final subject = test.subjectId != null
                      ? subjectMap[test.subjectId]
                      : null;
                  final passed = test.score >= AppConstants.passingTestScore;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: passed
                              ? colorScheme.primaryContainer
                              : colorScheme.errorContainer,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            passed ? Icons.check_circle : Icons.cancel,
                            color: passed
                                ? colorScheme.primary
                                : colorScheme.error,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  subject?.name ?? 'No Subject',
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    fontFamily: 'Questrial',
                                  ),
                                ),
                                if (test.academicSession != null &&
                                    test.academicSession!.trim().isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Session: ${test.academicSession}',
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                      fontFamily: 'Questrial',
                                    ),
                                  ),
                                ],
                                if (test.label != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    test.label!,
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                      fontFamily: 'Questrial',
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            '${test.score}%',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                              fontFamily: 'Questrial',
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: Icon(
                              Icons.edit_outlined,
                              size: 18,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            onPressed: () => _editTest(context, test, subjectMap, studentYear),
                            tooltip: 'Edit test',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: colorScheme.error,
                            ),
                            onPressed: () => _deleteTest(context, test),
                            tooltip: 'Delete test',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
              if (summary.totalTests == 0)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No test records found',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontFamily: 'Questrial',
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(
            'Error loading tests: $err',
            style: TextStyle(color: colorScheme.error, fontSize: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentsTab(ColorScheme colorScheme) {
    final paymentsAsync =
        ref.watch(paymentSummaryForStudentProvider(widget.student.id));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: paymentsAsync.when(
        data: (summary) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _statCard(
                'Total Paid',
                CurrencyUtils.formatRand(summary.totalPaid),
                colorScheme,
              ),
              const SizedBox(height: 16),
              _statCard(
                'Balance',
                CurrencyUtils.formatRand(summary.balance),
                colorScheme,
                highlight: true,
              ),
              const SizedBox(height: 16),
              _statCard(
                'Tuition Amount',
                CurrencyUtils.formatRand(AppConstants.fullTuitionAmount),
                colorScheme,
              ),
              if (summary.paymentsByYear.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(
                  'Payment Breakdown by Year',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    fontFamily: 'Questrial',
                  ),
                ),
                const SizedBox(height: 12),
                ...summary.paymentsByYear.entries.map((entry) {
                  final payment = entry.value;
                  final yearTotal = payment.jan +
                      payment.feb +
                      payment.mar +
                      payment.apr +
                      payment.may +
                      payment.jun +
                      payment.jul +
                      payment.aug +
                      payment.sep +
                      payment.oct +
                      payment.nov +
                      payment.dec +
                      payment.lumpSum;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Year ${entry.key}',
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  fontFamily: 'Questrial',
                                ),
                              ),
                              Text(
                                CurrencyUtils.formatRand(yearTotal),
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  fontFamily: 'Questrial',
                                ),
                              ),
                            ],
                          ),
                          if (payment.lumpSum > 0) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Lump Sum: ${CurrencyUtils.formatRand(payment.lumpSum)}',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                                fontFamily: 'Questrial',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],
              if (summary.totalPaid == 0)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No payment records found',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontFamily: 'Questrial',
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Text(
            'Error loading payments: $err',
            style: TextStyle(color: colorScheme.error, fontSize: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildMinistryTab(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.hourglass_empty_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Ministry Hours',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 18,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This feature is coming soon',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMissionsTab(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.public_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'Missions',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 18,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This feature is coming soon',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkboxRow(
    String label,
    bool value,
    ColorScheme colorScheme,
    Color redColor,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: [
                Icon(
                  value ? Icons.check_circle : Icons.circle_outlined,
                  color: value ? redColor : colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  value ? 'Yes' : 'No',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(
    String label,
    String value,
    ColorScheme colorScheme, {
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: highlight
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: highlight
            ? Border.all(color: colorScheme.primaryContainer, width: 2)
            : null,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              fontFamily: 'Questrial',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editTest(BuildContext context, Test test, Map<int, Subject> subjectMap, String studentYear) async {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final redColor = isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final messenger = ScaffoldMessenger.of(context);
    
    final scoreController = TextEditingController(text: test.score.toString());
    final labelController = TextEditingController(text: test.label ?? '');
    
    // Get subjects - use valueOrNull to get the current value or null if loading/error
    final subjectsAsync = ref.read(subjectsForYearStreamProvider(studentYear));
    final subjects = subjectsAsync.valueOrNull ?? [];
    final subjectList = subjects.map((s) => s.id).toList();
    
    // If no subjects available, show error
    if (subjects.isEmpty && !subjectsAsync.isLoading) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              subjectsAsync.hasError 
                ? 'Error loading subjects: ${subjectsAsync.error}'
                : 'No subjects available for $studentYear',
            ),
          ),
        );
      }
      return;
    }
    
    // Use a StatefulBuilder to manage the selectedSubjectId state
    int? selectedSubjectId = test.subjectId;
    
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: isDark ? AppColors.surfaceDarkElevated : AppColors.charisWhite,
          title: Text(
            'Edit Test',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 18,
              fontFamily: 'Questrial',
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SearchableDropdown<int>(
                  items: subjectList,
                  selectedValue: selectedSubjectId,
                  hint: 'Select subject...',
                  searchHint: 'Search subjects...',
                  itemBuilder: (context, subjectId) {
                    final subject = subjectMap[subjectId];
                    return Text(
                      subject?.name ?? 'Unknown',
                      style: const TextStyle(
                        color: AppColors.charisBlack,
                        fontSize: 14,
                        fontFamily: 'Questrial',
                      ),
                    );
                  },
                  displayTextBuilder: (subjectId) {
                    final subject = subjectMap[subjectId];
                    return subject?.name ?? 'Unknown';
                  },
                  searchFilter: (subjectId, query) {
                    final subject = subjectMap[subjectId];
                    return subject?.name.toLowerCase().contains(query.toLowerCase()) ?? false;
                  },
                  onChanged: (value) {
                    setDialogState(() {
                      selectedSubjectId = value;
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: scoreController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: 'Score (0-100)',
                    labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: labelController,
                  decoration: InputDecoration(
                    labelText: 'Notes (optional)',
                    labelStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(
                'Cancel',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(backgroundColor: redColor),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    
    if (result == true) {
      final auth = ref.read(authStateProvider).valueOrNull;
      if (auth is! Authenticated) {
        messenger.showSnackBar(
          const SnackBar(content: Text('You must be logged in to edit tests')),
        );
        return;
      }
      
      try {
        final score = int.tryParse(scoreController.text) ?? 0;
        final label = labelController.text.trim().isEmpty ? null : labelController.text.trim();
        
        final repo = ref.read(testRepositoryProvider);
        await repo.updateTest(
          test.id,
          score: score,
          label: label,
          subjectId: selectedSubjectId,
          userRole: auth.role,
          userId: auth.user.id,
        );
        
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Test updated successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Error updating test: $e')),
          );
        }
      }
    }
  }

  Future<void> _deleteTest(BuildContext context, Test test) async {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final messenger = ScaffoldMessenger.of(context);
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? AppColors.surfaceDarkElevated : AppColors.charisWhite,
        title: Text(
          'Delete Test',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 18,
            fontFamily: 'Questrial',
          ),
        ),
        content: Text(
          'Are you sure you want to delete this test record? This action cannot be undone.',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      final auth = ref.read(authStateProvider).valueOrNull;
      if (auth is! Authenticated) {
        messenger.showSnackBar(
          const SnackBar(content: Text('You must be logged in to delete tests')),
        );
        return;
      }
      
      try {
        final repo = ref.read(testRepositoryProvider);
        await repo.deleteTest(
          test.id,
          userRole: auth.role,
          userId: auth.user.id,
        );
        
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Test deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('Error deleting test: $e')),
          );
        }
      }
    }
  }
}
