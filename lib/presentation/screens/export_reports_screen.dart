import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/core/utils/date_utils.dart'
    as app_date_utils;
import 'package:charis_student_care/data/services/report_service.dart';
import 'package:charis_student_care/presentation/providers/academic_session_providers.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/report_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';

enum ReportFormat { pdf, excel }

/// Export & Reports screen: filters, preview, and Export/Download actions.
class ExportReportsScreen extends ConsumerStatefulWidget {
  const ExportReportsScreen({super.key, this.initialReportType});

  /// Optional report type from route query param (e.g. from /reports?type=cohort-summary).
  final String? initialReportType;

  @override
  ConsumerState<ExportReportsScreen> createState() =>
      _ExportReportsScreenState();
}

String _defaultReportSession() {
  final now = DateTime.now();
  final y = now.year;
  return now.month >= 7 ? '$y-${y + 1}' : '${y - 1}-$y';
}

class _ExportReportsScreenState extends ConsumerState<ExportReportsScreen> {
  ReportFormat _reportFormat = ReportFormat.pdf;
  ReportType _selectedReportType = ReportType.studentSummary;
  String? _selectedClass;
  String? _selectedSession;
  String _selectedMode = 'Full-time';
  late DateTime _dateStart;
  late DateTime _dateEnd;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateStart = DateTime(now.year, 1, 1);
    _dateEnd = DateTime(now.year, 12, 31);
    _selectedClass = null; // Set from reportClassOptionsForCurrentUserProvider when loaded
    _selectedSession = _defaultReportSession();
    _selectedReportType = ReportType.fromQueryParam(widget.initialReportType);
  }

  /// Report types visible to the current user (payment types only for Admin).
  List<ReportType> _visibleReportTypes(WidgetRef ref) {
    final auth = ref.read(authStateProvider).valueOrNull;
    final canSeePayments = auth is Authenticated && RolePermissions.canManageFinancials(auth.role);
    const types = ReportType.values;
    if (canSeePayments) return types;
    return types
        .where((t) => t != ReportType.payments && t != ReportType.missionsPayment)
        .toList();
  }

  ReportFilters get _filters => ReportFilters(
        mode: _selectedMode,
        dateStart: _dateStart,
        dateEnd: _dateEnd,
        year: null,
        academicSession: _selectedSession,
        classFilter: _selectedClass,
      );

  Future<void> _pickDateStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked.isBefore(_dateEnd)) {
      setState(() => _dateStart = picked);
    }
  }

  Future<void> _pickDateEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateEnd,
      firstDate: _dateStart,
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _dateEnd = picked);
    }
  }

  String _baseNameForType(ReportType type) {
    final slug = type.queryParam.replaceAll('-', '_');
    return 'Report_$slug';
  }

  Future<void> _exportReport({ReportFormat? forceFormat}) async {
    final format = forceFormat ?? _reportFormat;
    setState(() => _isExporting = true);
    try {
      final extension = format == ReportFormat.pdf ? 'pdf' : 'xlsx';
      final baseName = _baseNameForType(_selectedReportType);
      final suggestedName =
          '${baseName}_${DateFormat('yyyy-MM-dd').format(DateTime.now())}.$extension';

      Uint8List bytes;
      final auth = ref.read(authStateProvider).valueOrNull;
      final includePaymentColumns = auth is Authenticated && RolePermissions.canManageFinancials(auth.role);
      switch (_selectedReportType) {
        case ReportType.studentSummary:
          final rows = await ref.read(reportDataProvider(_filters).future);
          if (format == ReportFormat.pdf) {
            bytes = await ReportService.buildPdf(rows, _filters, includePaymentColumns: includePaymentColumns);
          } else {
            bytes = ReportService.buildExcel(rows, _filters, includePaymentColumns: includePaymentColumns);
          }
          break;
        case ReportType.cohortSummary:
          final rows = await ref.read(cohortReportDataProvider.future);
          if (format == ReportFormat.pdf) {
            bytes = await ReportService.buildCohortSummaryPdf(rows, includeBalanceColumn: includePaymentColumns);
          } else {
            bytes = ReportService.buildCohortSummaryExcel(rows, includeBalanceColumn: includePaymentColumns);
          }
          break;
        case ReportType.students:
          final rows = await ref.read(studentsReportDataProvider.future);
          const headers = ['Surname', 'First name', 'Status', 'Mode', 'Admission year', 'Class'];
          final tableRows = rows.map((s) => [
            s.surname,
            s.firstName,
            s.status,
            s.mode ?? '—',
            s.admissionYear ?? '—',
            '—',
          ],).toList();
          const title = 'Students Report';
          if (format == ReportFormat.pdf) {
            bytes = await ReportService.buildTablePdf(title, headers, tableRows);
          } else {
            bytes = ReportService.buildTableExcel(title, 'Students', headers, tableRows);
          }
          break;
        case ReportType.subjects:
          final rows = await ref.read(subjectsReportDataProvider.future);
          const headers = ['Subject', 'Class'];
          final tableRows = rows.map((s) => [s.name, s.className]).toList();
          const title = 'Subjects Report';
          if (format == ReportFormat.pdf) {
            bytes = await ReportService.buildTablePdf(title, headers, tableRows);
          } else {
            bytes = ReportService.buildTableExcel(title, 'Subjects', headers, tableRows);
          }
          break;
        case ReportType.attendance:
          final rows = await ref.read(attendanceReportDataProvider(_filters).future);
          const headers = ['Date', 'Student', 'Present', 'Notes'];
          final tableRows = rows.map((r) => [
            app_date_utils.DateUtils.formatIsoDate(r.date),
            r.studentName,
            r.present ? 'Yes' : 'No',
            r.notes ?? '—',
          ],).toList();
          const title = 'Attendance Report';
          if (format == ReportFormat.pdf) {
            bytes = await ReportService.buildTablePdf(title, headers, tableRows);
          } else {
            bytes = ReportService.buildTableExcel(title, 'Attendance', headers, tableRows);
          }
          break;
        case ReportType.ministryHours:
          final rows = await ref.read(ministryReportDataProvider(_filters).future);
          const headers = ['Date', 'Student', 'Type', 'Hours', 'Approved', 'Supervisor'];
          final tableRows = rows.map((r) => [
            app_date_utils.DateUtils.formatIsoDate(r.date),
            r.studentName,
            r.ministryType,
            r.hours.toStringAsFixed(1),
            r.approved ? 'Yes' : 'No',
            r.supervisor ?? '—',
          ],).toList();
          const title = 'Ministry Hours Report';
          if (format == ReportFormat.pdf) {
            bytes = await ReportService.buildTablePdf(title, headers, tableRows);
          } else {
            bytes = ReportService.buildTableExcel(title, 'Ministry Hours', headers, tableRows);
          }
          break;
        case ReportType.tests:
          final rows = await ref.read(testsReportDataProvider(_filters).future);
          const headers = ['Date', 'Student', 'Score', 'Label', 'Subject'];
          final tableRows = rows.map((r) => [
            app_date_utils.DateUtils.formatIsoDate(r.createdAt),
            r.studentName,
            '${r.score}',
            r.label ?? '—',
            r.subjectName ?? '—',
          ],).toList();
          const title = 'Tests Report';
          if (format == ReportFormat.pdf) {
            bytes = await ReportService.buildTablePdf(title, headers, tableRows);
          } else {
            bytes = ReportService.buildTableExcel(title, 'Tests', headers, tableRows);
          }
          break;
        case ReportType.payments:
          final rows = await ref.read(paymentsReportDataProvider(_filters).future);
          const headers = ['Student', 'Year', 'Total paid'];
          final tableRows = rows.map((r) => [
            r.studentName,
            r.year,
            r.totalPaid.toStringAsFixed(2),
          ],).toList();
          const title = 'Payments Report';
          if (format == ReportFormat.pdf) {
            bytes = await ReportService.buildTablePdf(title, headers, tableRows);
          } else {
            bytes = ReportService.buildTableExcel(title, 'Payments', headers, tableRows);
          }
          break;
        case ReportType.missionsPayment:
          final rows = await ref.read(missionPaymentsReportDataProvider.future);
          const headers = ['Payment date', 'Student', 'Amount'];
          final tableRows = rows.map((r) => [
            app_date_utils.DateUtils.formatIsoDate(r.paymentDate),
            r.studentName,
            r.amount.toStringAsFixed(2),
          ],).toList();
          const title = 'Missions Payment Report';
          if (format == ReportFormat.pdf) {
            bytes = await ReportService.buildTablePdf(title, headers, tableRows);
          } else {
            bytes = ReportService.buildTableExcel(title, 'Missions Payment', headers, tableRows);
          }
          break;
        case ReportType.missionLocations:
          final rows = await ref.read(missionLocationsReportDataProvider.future);
          const headers = ['Name', 'Description', 'Active'];
          final tableRows = rows.map((r) => [
            r.name,
            r.description ?? '—',
            r.isActive ? 'Yes' : 'No',
          ],).toList();
          const title = 'Mission Locations Report';
          if (format == ReportFormat.pdf) {
            bytes = await ReportService.buildTablePdf(title, headers, tableRows);
          } else {
            bytes = ReportService.buildTableExcel(title, 'Mission Locations', headers, tableRows);
          }
          break;
      }

      final downloadsDir = await getDownloadsDirectory();
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save report',
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
        } catch (writeError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Export failed: $writeError'),
                backgroundColor: Theme.of(context).colorScheme.error,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          debugPrint('Export write error: $writeError');
        }
      }
    } catch (e, st) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      debugPrint('Export error: $e\n$st');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _buildModeField(ColorScheme colorScheme) {
    final modeOptions = ref.watch(modeOptionsForCurrentUserProvider);
    if (modeOptions.length == 1) {
      if (_selectedMode != modeOptions[0]) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedMode = modeOptions[0]);
        });
      }
      return InputDecorator(
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          isDense: true,
        ),
        child: Text(
          modeOptions[0],
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 14,
          ),
        ),
      );
    }
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: _selectedMode,
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        isDense: true,
      ),
      items: modeOptions
          .map((m) => DropdownMenuItem(
                value: m,
                child: Text(m),
              ),)
          .toList(),
      onChanged: (v) =>
          setState(() => _selectedMode = v ?? _selectedMode),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final modeOptions = ref.watch(modeOptionsForCurrentUserProvider);
    if (modeOptions.length == 1 && _selectedMode != modeOptions[0]) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedMode = modeOptions[0]);
      });
    }
    final authAsync = ref.watch(authStateProvider);
    final auth = authAsync.valueOrNull;
    final visibleTypes = _visibleReportTypes(ref);
    if (auth is Authenticated &&
        !RolePermissions.canManageFinancials(auth.role) &&
        (_selectedReportType == ReportType.payments ||
            _selectedReportType == ReportType.missionsPayment)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedReportType = ReportType.studentSummary);
      });
    }
    final classOptionsAsync = ref.watch(reportClassOptionsForCurrentUserProvider);
    classOptionsAsync.whenData((classOptions) {
      if (classOptions.isNotEmpty && (_selectedClass == null || !classOptions.contains(_selectedClass))) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedClass = classOptions.first);
        });
      }
    });
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final dateRangeStr =
        '${app_date_utils.DateUtils.formatIsoDate(_dateStart)} – ${app_date_utils.DateUtils.formatIsoDate(_dateEnd)}';

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Export & Reports',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 24,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 300,
                  child: _buildLeftPanel(colorScheme, redColor, isDark, visibleTypes, classOptionsAsync),
                ),
                const SizedBox(width: 32),
                Expanded(
                  child: _buildRightPanel(
                    colorScheme,
                    redColor,
                    isDark,
                    dateRangeStr,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftPanel(
    ColorScheme colorScheme,
    Color redColor,
    bool isDark,
    List<ReportType> visibleReportTypes,
    AsyncValue<List<String>> classOptionsAsync,
  ) {
    return Card(
      elevation: 0,
      color: isDark
          ? AppColors.surfaceDarkElevated
          : colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Report source',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      fontFamily: 'Questrial',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ReportType>(
                    isExpanded: true,
                    initialValue: _selectedReportType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    items: visibleReportTypes
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t.label),
                            ),)
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedReportType = v);
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Output format',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      fontFamily: 'Questrial',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                            _formatChip(
                        label: 'PDF Summary',
                        selected: _reportFormat == ReportFormat.pdf,
                        onTap: () =>
                            setState(() => _reportFormat = ReportFormat.pdf),
                        redColor: redColor,
                        colorScheme: colorScheme,
                      ),
                      const SizedBox(width: 8),
                      _formatChip(
                        label: 'Excel Export',
                        selected: _reportFormat == ReportFormat.excel,
                        onTap: () => setState(
                            () => _reportFormat = ReportFormat.excel,),
                        redColor: redColor,
                        colorScheme: colorScheme,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Class',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      fontFamily: 'Questrial',
                    ),
                  ),
                  const SizedBox(height: 8),
                  classOptionsAsync.when(
                    data: (classOptions) {
                      final options = classOptions.isEmpty ? ['—'] : classOptions;
                      final value = _selectedClass != null && options.contains(_selectedClass)
                          ? _selectedClass!
                          : options.first;
                      return DropdownButtonFormField<String>(
                        isExpanded: true,
                        key: ValueKey<String?>(_selectedClass),
                        initialValue: value,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        items: options
                            .map((c) => DropdownMenuItem(
                                  value: c,
                                  child: Text(c),
                                ),)
                            .toList(),
                        onChanged: (v) => setState(() => _selectedClass = v),
                      );
                    },
                    loading: () => DropdownButtonFormField<String>(
                      initialValue: _selectedClass ?? '—',
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(value: _selectedClass ?? '—', child: Text(_selectedClass ?? '—')),
                      ],
                      onChanged: null,
                    ),
                    error: (_, __) => DropdownButtonFormField<String>(
                      initialValue: _selectedClass ?? '—',
                      isExpanded: true,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem(value: _selectedClass ?? '—', child: Text(_selectedClass ?? '—')),
                      ],
                      onChanged: null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Academic session',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      fontFamily: 'Questrial',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Consumer(
                    builder: (context, ref, _) {
                      final sessionOptionsAsync = ref.watch(academicSessionOptionsProvider);
                      return sessionOptionsAsync.when(
                        data: (options) {
                          final list = options.isNotEmpty ? options : [_defaultReportSession()];
                          final value = _selectedSession != null && list.contains(_selectedSession)
                              ? _selectedSession!
                              : list.first;
                          if (_selectedSession == null || !list.contains(_selectedSession!)) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) setState(() => _selectedSession = list.first);
                            });
                          }
                          return DropdownButtonFormField<String>(
                            initialValue: value,
                            isExpanded: true,
                            decoration: InputDecoration(
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              isDense: true,
                            ),
                            items: list
                                .map((s) => DropdownMenuItem(
                                      value: s,
                                      child: Text(s),
                                    ),)
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _selectedSession = v),
                          );
                        },
                        loading: () => DropdownButtonFormField<String>(
                          initialValue: _selectedSession ?? _defaultReportSession(),
                          isExpanded: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: _selectedSession ?? _defaultReportSession(),
                              child: Text(_selectedSession ?? _defaultReportSession()),
                            ),
                          ],
                          onChanged: null,
                        ),
                        error: (_, __) => DropdownButtonFormField<String>(
                          initialValue: _selectedSession ?? _defaultReportSession(),
                          isExpanded: true,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            isDense: true,
                          ),
                          items: [
                            DropdownMenuItem(
                              value: _selectedSession ?? _defaultReportSession(),
                              child: Text(_selectedSession ?? _defaultReportSession()),
                            ),
                          ],
                          onChanged: null,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Mode',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      fontFamily: 'Questrial',
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildModeField(colorScheme),
                  const SizedBox(height: 16),
                  Text(
                    'Date Range',
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      fontFamily: 'Questrial',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDateStart,
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                            app_date_utils.DateUtils.formatIsoDate(_dateStart),
                            style: const TextStyle(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text('–', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickDateEnd,
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: Text(
                            app_date_utils.DateUtils.formatIsoDate(_dateEnd),
                            style: const TextStyle(fontSize: 13),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _formatChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    required Color redColor,
    required ColorScheme colorScheme,
  }) {
    return Material(
      color: selected
          ? redColor.withValues(alpha: 0.15)
          : colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? redColor : colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? redColor : colorScheme.onSurface,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              fontSize: 13,
              fontFamily: 'Questrial',
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRightPanel(
    ColorScheme colorScheme,
    Color redColor,
    bool isDark,
    String dateRangeStr,
  ) {
    final isPdf = _reportFormat == ReportFormat.pdf;
    final previewTitle = isPdf
        ? 'Student Summary PDF Preview'
        : 'Student Summary Report Preview';

    return Card(
      elevation: 0,
      color: isDark
          ? AppColors.surfaceDarkElevated
          : colorScheme.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              previewTitle,
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colorScheme.outlineVariant),
              ),
              child: Center(
                child: Icon(
                  isPdf ? Icons.picture_as_pdf : Icons.table_chart,
                  size: 48,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'This ${isPdf ? 'PDF summary' : 'report'} includes student '
              'attendance, test scores, and payment overviews for the '
              'selected period ($dateRangeStr). It\'s designed for quick '
              'review and record-keeping.',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isExporting ? null : () => _exportReport(),
              icon: _isExporting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.onPrimary,
                      ),
                    )
                  : Icon(Icons.upload_file, color: colorScheme.onPrimary),
              label: Text(_isExporting ? 'Exporting…' : 'Export Report'),
              style: FilledButton.styleFrom(
                backgroundColor: redColor,
                foregroundColor: colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  fontFamily: 'Questrial',
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isExporting
                        ? null
                        : () => _exportReport(forceFormat: ReportFormat.pdf),
                    icon: const Icon(Icons.picture_as_pdf, size: 20),
                    label: const Text('Download PDF'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isExporting
                        ? null
                        : () => _exportReport(forceFormat: ReportFormat.excel),
                    icon: const Icon(Icons.table_chart, size: 20),
                    label: const Text('Download Excel'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
