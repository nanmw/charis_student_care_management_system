import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/services/report_service.dart';
import 'package:charis_student_care/presentation/providers/report_providers.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:charis_student_care/core/utils/currency_utils.dart';
import 'package:charis_student_care/core/utils/date_utils.dart'
    as app_date_utils;
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/ministry_providers.dart';
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
  bool _isExporting = false;

  ReportFilters get _exportFilters {
    final now = DateTime.now();
    return ReportFilters(
      mode: widget.student.mode ?? 'Full-time',
      dateStart: DateTime(now.year, 1, 1),
      dateEnd: DateTime(now.year, 12, 31),
      year: widget.student.admissionYear ?? now.year.toString(),
    );
  }

  Future<void> _exportStudentSummary({required bool asPdf}) async {
    setState(() => _isExporting = true);
    try {
      final row = await ref.read(singleStudentReportRowProvider(
        (studentId: widget.student.id, filters: _exportFilters,),
      ).future,);
      if (row == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not build report for this student.')),
          );
        }
        return;
      }
      final extension = asPdf ? 'pdf' : 'xlsx';
      final name = asPdf ? 'Student_Summary_Report' : 'Student_Summary_Export';
      final safeName = '${widget.student.surname}_${widget.student.firstName}'
          .replaceAll(RegExp(r'[^\w\s-]'), '')
          .replaceAll(RegExp(r'\s+'), '_');
      final suggestedName =
          '${name}_${safeName}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.$extension';
      final auth = ref.read(authStateProvider).valueOrNull;
      final includePaymentColumns = auth is Authenticated && RolePermissions.canManageFinancials(auth.role);
      final Uint8List bytes = asPdf
          ? await ReportService.buildPdf([row], _exportFilters, includePaymentColumns: includePaymentColumns)
          : ReportService.buildExcel([row], _exportFilters, includePaymentColumns: includePaymentColumns);
      final downloadsDir = await getDownloadsDirectory();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save student summary',
        fileName: suggestedName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: [extension],
        initialDirectory: downloadsDir?.path,
      );
      if (mounted && path != null && path.isNotEmpty) {
        try {
          String filePath = path;
          if (!filePath.toLowerCase().endsWith('.$extension')) {
            filePath = '$filePath.$extension';
          }
          await File(filePath).writeAsBytes(bytes);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Report saved to $filePath'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Export failed: $e'),
                backgroundColor: Theme.of(context).colorScheme.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
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
                    icon:
                        Icon(Icons.close, color: colorScheme.onSurfaceVariant),
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
                ],
              ),
            ),
            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(
                children: [
                  RoleGuard(
                    canShow: RolePermissions.canExportReports,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _isExporting
                              ? null
                              : () => _exportStudentSummary(asPdf: true),
                          icon: _isExporting
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.primary,
                                  ),
                                )
                              : const Icon(Icons.picture_as_pdf, size: 18),
                          label: const Text('Download PDF'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.onSurfaceVariant,
                            side: BorderSide(color: colorScheme.outline),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12,),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _isExporting
                              ? null
                              : () => _exportStudentSummary(asPdf: false),
                          icon: const Icon(Icons.table_chart, size: 18),
                          label: const Text('Download Excel'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.onSurfaceVariant,
                            side: BorderSide(color: colorScheme.outline),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12,),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
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
                ],
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
          _ClassYearRow(classId: widget.student.classId, colorScheme: colorScheme),
          _row('Mode', widget.student.mode ?? '—', colorScheme),
          _row('Admission year', widget.student.admissionYear ?? '—',
              colorScheme,),
          _row('Status', widget.student.status, colorScheme),
          _row('Phone', widget.student.contactInfo ?? '—', colorScheme),
          _row('Email', widget.student.email ?? '—', colorScheme),
          const SizedBox(height: 16),
          _checkboxRow(
              'Handbook', widget.student.handbook, colorScheme, redColor,),
          _checkboxRow('Media Release', widget.student.mediaRelease,
              colorScheme, redColor,),
          _checkboxRow('Accident Waiver', widget.student.accidentWaiver,
              colorScheme, redColor,),
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
                ...summary.recentDates.map(
                  (date) => Padding(
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
                  ),
                ),
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
    final classId = widget.student.classId;
    final studentMode = widget.student.mode ?? 'Full-time';
    final testsAsync = ref.watch(
      testSummaryForStudentProvider(
          (widget.student.id, classId, studentMode),),
    );
    final subjectsAsync = ref.watch(subjectsForClassStreamProvider(classId ?? 0));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: testsAsync.when(
        data: (summary) {
          // Handle subjects loading/error states separately
          if (subjectsAsync.isLoading) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _statCard(
                    'Total Tests', summary.totalTests.toString(), colorScheme,),
                const SizedBox(height: 16),
                _statCard(
                  'Outstanding Tests',
                  summary.outstandingTests.toString(),
                  colorScheme,
                  highlight: summary.outstandingTests > 0,
                ),
                const SizedBox(height: 16),
                _statCard(
                  'Failed Tests',
                  summary.failedTestsList.length.toString(),
                  colorScheme,
                  highlight: summary.failedTestsList.isNotEmpty,
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
                _statCard(
                    'Total Tests', summary.totalTests.toString(), colorScheme,),
                const SizedBox(height: 16),
                _statCard(
                  'Outstanding Tests',
                  summary.outstandingTests.toString(),
                  colorScheme,
                  highlight: summary.outstandingTests > 0,
                ),
                const SizedBox(height: 16),
                _statCard(
                  'Failed Tests',
                  summary.failedTestsList.length.toString(),
                  colorScheme,
                  highlight: summary.failedTestsList.isNotEmpty,
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
              _statCard(
                  'Total Tests', summary.totalTests.toString(), colorScheme,),
              const SizedBox(height: 16),
              _statCard(
                'Outstanding Tests',
                summary.outstandingTests.toString(),
                colorScheme,
                highlight: summary.outstandingTests > 0,
              ),
              const SizedBox(height: 16),
              _statCard(
                'Failed Tests',
                summary.failedTestsList.length.toString(),
                colorScheme,
                highlight: summary.failedTestsList.isNotEmpty,
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
              Text(
                'Passed tests (current academic year)',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Questrial',
                ),
              ),
              const SizedBox(height: 12),
              if (summary.passedTestsList.isEmpty)
                Text(
                  'No passed tests for current academic year.',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                )
              else
                ...summary.passedTestsList.map((test) {
                  final subject = test.subjectId != null
                      ? subjectMap[test.subjectId]
                      : null;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.primaryContainer,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            color: colorScheme.primary,
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
                                const SizedBox(height: 2),
                                Text(
                                  app_date_utils.DateUtils.formatDisplayDate(
                                      test.createdAt,),
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                    fontFamily: 'Questrial',
                                  ),
                                ),
                                if (test.label != null &&
                                    test.label!.trim().isNotEmpty) ...[
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
                            onPressed: () => _editTest(
                                context, test, subjectMap, classId,),
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
              const SizedBox(height: 24),
              Text(
                'Failed tests (current academic year)',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Questrial',
                ),
              ),
              const SizedBox(height: 12),
              if (summary.failedTestsList.isEmpty)
                Text(
                  'No failed tests for current academic year.',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                )
              else
                ...summary.failedTestsList.map((test) {
                  final subject = test.subjectId != null
                      ? subjectMap[test.subjectId]
                      : null;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.errorContainer,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cancel,
                            color: colorScheme.error,
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
                                const SizedBox(height: 2),
                                Text(
                                  app_date_utils.DateUtils.formatDisplayDate(
                                      test.createdAt,),
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                    fontFamily: 'Questrial',
                                  ),
                                ),
                                if (test.label != null &&
                                    test.label!.trim().isNotEmpty) ...[
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
                            onPressed: () => _editTest(
                                context, test, subjectMap, classId,),
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
              const SizedBox(height: 24),
              Text(
                'Outstanding tests (current academic year)',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  fontFamily: 'Questrial',
                ),
              ),
              const SizedBox(height: 12),
              if (summary.outstandingItems.isEmpty)
                Text(
                  'No outstanding tests for current academic year.',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                )
              else
                ...summary.outstandingItems.map((item) {
                  final subject = subjectMap[item.subjectId];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: colorScheme.outlineVariant,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.hourglass_empty_outlined,
                            color: colorScheme.onSurfaceVariant,
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
                                const SizedBox(height: 2),
                                Text(
                                  app_date_utils.DateUtils.formatDisplayDate(
                                      item.dateWhenOutstanding,),
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
                    ),
                  );
                }),
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
    final auth = ref.watch(authStateProvider).valueOrNull;
    if (auth is! Authenticated || !RolePermissions.canManageFinancials(auth.role)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Payment information is only available to administrators.',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
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
    final student = widget.student;
    final entriesAsync =
        ref.watch(ministryEntriesForStudentProvider(student.id));
    final hasClassAndMode =
        student.classId != null && student.mode != null && student.mode!.trim().isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasClassAndMode) ...[
            _buildMinistrySummaryWithRequirement(
              colorScheme,
              student.classId!,
              student.mode!,
              student.id,
            ),
          ] else ...[
            Text(
              'Class or study mode not set. Showing total hours only.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 12),
            entriesAsync.when(
              data: (entries) {
                final total =
                    entries.fold<double>(0.0, (s, e) => s + e.hours);
                return _statCard(
                  'Total hours',
                  total.toStringAsFixed(1),
                  colorScheme,
                );
              },
              loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ), ),
              error: (err, _) => Text(
                'Error: $err',
                style: TextStyle(
                  color: colorScheme.error,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Ministry entries',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 16,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 12),
          entriesAsync.when(
            data: (entries) {
              if (entries.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'No ministry entries recorded',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 14,
                      fontFamily: 'Questrial',
                    ),
                  ),
                );
              }
              return Column(
                children: entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.ministryType,
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                    fontFamily: 'Questrial',
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  app_date_utils.DateUtils.formatDisplayDate(
                                    entry.date,
                                  ),
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 12,
                                    fontFamily: 'Questrial',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${entry.hours.toStringAsFixed(1)} hrs',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              fontFamily: 'Questrial',
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            entry.approved
                                ? Icons.check_circle
                                : Icons.pending_outlined,
                            size: 20,
                            color: entry.approved
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (err, _) => Text(
              'Error loading entries: $err',
              style: TextStyle(
                color: colorScheme.error,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMinistrySummaryWithRequirement(
    ColorScheme colorScheme,
    int classId,
    String studyMode,
    int studentId,
  ) {
    final summaryAsync =
        ref.watch(ministryHoursSummaryProvider((classId, studyMode)));
    final classAsync = ref.watch(classByIdProvider(classId));
    final yearLevel = classAsync.valueOrNull?.sortOrder ?? 1;
    final reqMap = studyMode == 'Full-time'
        ? AppConstants.ministryHoursRequirements['FullTime']
        : AppConstants.ministryHoursRequirements['Hybrid'];
    final requiredHours = (reqMap != null ? reqMap[yearLevel] : null) ?? 0;
    final requirementText =
        AppConstants.ministryHoursRequirementText(studyMode, yearLevel);

    return summaryAsync.when(
      data: (rows) {
        final matching = rows.where((r) => r.studentId == studentId);
        final row = matching.isEmpty ? null : matching.first;
        final term1 = row?.term1Hours ?? 0.0;
        final term2 = row?.term2Hours ?? 0.0;
        final term3 = row?.term3Hours ?? 0.0;
        final total = row?.totalHours ?? 0.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              requirementText,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 16),
            _statCard(
              'Term 1',
              '${term1.toStringAsFixed(1)} / $requiredHours hrs',
              colorScheme,
            ),
            const SizedBox(height: 12),
            _statCard(
              'Term 2',
              '${term2.toStringAsFixed(1)} / $requiredHours hrs',
              colorScheme,
            ),
            const SizedBox(height: 12),
            _statCard('Term 3', '${term3.toStringAsFixed(1)} hrs', colorScheme),
            const SizedBox(height: 12),
            _statCard('Total', total.toStringAsFixed(1), colorScheme, highlight: true),
          ],
        );
      },
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (err, _) => Text(
        'Error loading summary: $err',
        style: TextStyle(
          color: colorScheme.error,
          fontSize: 14,
          fontFamily: 'Questrial',
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

  Future<void> _editTest(BuildContext context, Test test,
      Map<int, Subject> subjectMap, int? classId,) async {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final messenger = ScaffoldMessenger.of(context);

    final scoreController = TextEditingController(text: test.score.toString());
    final labelController = TextEditingController(text: test.label ?? '');

    final subjectsAsync = ref.read(subjectsForClassStreamProvider(classId ?? 0));
    final subjects = subjectsAsync.valueOrNull ?? [];
    final subjectList = subjects.map((s) => s.id).toList();

    if (subjects.isEmpty && !subjectsAsync.isLoading) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              subjectsAsync.hasError
                  ? 'Error loading subjects: ${subjectsAsync.error}'
                  : 'No subjects available for this class',
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
          backgroundColor:
              isDark ? AppColors.surfaceDarkElevated : AppColors.charisWhite,
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
                    return subject?.name
                            .toLowerCase()
                            .contains(query.toLowerCase()) ??
                        false;
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
        final label = labelController.text.trim().isEmpty
            ? null
            : labelController.text.trim();

        final repo = ref.read(testRepositoryProvider);
        await repo.updateTest(
          test.id,
          score: score,
          label: label,
          subjectId: selectedSubjectId,
          userRole: auth.role,
          userId: auth.user.id,
          userDisplayName: auth.user.displayName,
          screen: 'Tests',
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
        backgroundColor:
            isDark ? AppColors.surfaceDarkElevated : AppColors.charisWhite,
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
          const SnackBar(
              content: Text('You must be logged in to delete tests'),),
        );
        return;
      }

      try {
        final repo = ref.read(testRepositoryProvider);
        await repo.deleteTest(
          test.id,
          userRole: auth.role,
          userId: auth.user.id,
          userDisplayName: auth.user.displayName,
          screen: 'Tests',
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

/// Displays "Year" row with class name from [classId].
class _ClassYearRow extends ConsumerWidget {
  const _ClassYearRow({this.classId, required this.colorScheme});

  final int? classId;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = classId != null
        ? ref.watch(classByIdProvider(classId!)).valueOrNull?.name ?? '—'
        : '—';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              'Year',
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
}
