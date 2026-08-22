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
import 'package:charis_student_care/core/utils/file_export_utils.dart';
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
  return DateTime.now().year.toString();
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
        classFilter: _selectedClass == null ||
                _selectedClass == kReportClassFilterAll
            ? null
            : _selectedClass,
      );

  bool _usesFilters(ReportType type) {
    return type != ReportType.cohortSummary &&
        type != ReportType.missionLocations;
  }

  bool _usesDateRange(ReportType type) {
    return type == ReportType.studentSummary ||
        type == ReportType.attendance ||
        type == ReportType.ministryHours ||
        type == ReportType.tests ||
        type == ReportType.payments ||
        type == ReportType.missionsPayment;
  }

  bool _usesSession(ReportType type) {
    return type == ReportType.studentSummary ||
        type == ReportType.attendance ||
        type == ReportType.ministryHours ||
        type == ReportType.tests ||
        type == ReportType.payments ||
        type == ReportType.missionsPayment;
  }

  bool _usesClassAndMode(ReportType type) {
    return _usesFilters(type);
  }

  /// Validates class/session filters; returns an error message or null if OK.
  Future<String?> _validateFiltersForExport() async {
    final filters = _filters;
    if (await reportClassFilterIsUnresolved(
      ref.read(classRepositoryProvider),
      filters,
    )) {
      return 'Selected class "${filters.classFilter}" was not found. Pick another class or All.';
    }
    if (_usesSession(_selectedReportType) &&
        await reportSessionFilterIsUnresolved(
          ref.read(academicSessionRepositoryProvider),
          filters,
        )) {
      return 'Selected academic session "${filters.academicSession}" was not found. Pick a valid session.';
    }
    return null;
  }

  Future<void> _pickDateStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && !picked.isAfter(_dateEnd)) {
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
    final validationError = await _validateFiltersForExport();
    if (validationError != null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(validationError),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

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
          final rows = await ref.read(studentsReportDataProvider(_filters).future);
          const headers = ['Surname', 'First name', 'Status', 'Mode', 'Admission year', 'Class'];
          final tableRows = rows.map((s) => [
            s.student.surname,
            s.student.firstName,
            s.student.status,
            s.student.mode ?? '—',
            s.student.admissionYear ?? '—',
            s.className,
          ],).toList();
          const title = 'Students Report';
          if (format == ReportFormat.pdf) {
            bytes = await ReportService.buildTablePdf(title, headers, tableRows);
          } else {
            bytes = ReportService.buildTableExcel(title, 'Students', headers, tableRows);
          }
          break;
        case ReportType.subjects:
          final rows = await ref.read(subjectsReportDataProvider(_filters).future);
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
          const title = 'Finances Report';
          if (format == ReportFormat.pdf) {
            bytes = await ReportService.buildTablePdf(title, headers, tableRows);
          } else {
            bytes = ReportService.buildTableExcel(title, 'Finances', headers, tableRows);
          }
          break;
        case ReportType.missionsPayment:
          final rows =
              await ref.read(missionPaymentsReportDataProvider(_filters).future);
          const headers = [
            'Student',
            'Trip',
            'Date',
            'Amount',
            'March',
            'April',
            'May',
            'June',
            'July',
            'Aug',
            'Sept',
            'Oct',
            'Paid to date',
            'Balance',
            'Comment',
          ];
          String money(double v) => v.toStringAsFixed(2);
          final tableRows = rows.map((r) => [
            r.studentName,
            r.tripSelected ?? '—',
            r.date != null
                ? app_date_utils.DateUtils.formatIsoDate(r.date!)
                : '—',
            money(r.amount),
            money(r.mar),
            money(r.apr),
            money(r.may),
            money(r.jun),
            money(r.jul),
            money(r.aug),
            money(r.sep),
            money(r.oct),
            money(r.paidToDate),
            money(r.balance),
            r.comment ?? '—',
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

      if (bytes.isEmpty) {
        throw StateError(
          'Generated report is empty. Please review filters and try again.',
        );
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
                content: Text(
                  FileExportUtils.userFacingSaveError(
                    writeError,
                    itemLabel: 'report',
                  ),
                ),
                backgroundColor: Theme.of(context).colorScheme.error,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 8),
              ),
            );
          }
          debugPrint('Export write error: $writeError');
        }
      }
    } catch (e, st) {
      if (mounted) {
        final message = e is FileSystemException ||
                e.toString().toLowerCase().contains('pathaccess') ||
                e.toString().toLowerCase().contains('errno =')
            ? FileExportUtils.userFacingSaveError(e, itemLabel: 'report')
            : e is StateError
                ? e.message
                : 'Export failed. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      debugPrint('Export error: $e\n$st');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _buildModeField(ColorScheme colorScheme, {required bool enabled}) {
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
      onChanged: enabled
          ? (v) => setState(() => _selectedMode = v ?? _selectedMode)
          : null,
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
      // Keep "All" as default; only reset if current selection is invalid.
      if (_selectedClass != null &&
          _selectedClass != kReportClassFilterAll &&
          classOptions.isNotEmpty &&
          !classOptions.contains(_selectedClass)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _selectedClass = kReportClassFilterAll);
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
    final usesDateRange = _usesDateRange(_selectedReportType);
    final usesSession = _usesSession(_selectedReportType);
    final usesClassAndMode = _usesClassAndMode(_selectedReportType);
    final isCohort = _selectedReportType == ReportType.cohortSummary;
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
                  if (isCohort) ...[
                    Text(
                      'Exports the current Dashboard cohort view. Class, mode, session, and date filters do not apply.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 12,
                        fontFamily: 'Questrial',
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
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
                      final options = [
                        kReportClassFilterAll,
                        ...classOptions,
                      ];
                      final value = _selectedClass != null &&
                              options.contains(_selectedClass)
                          ? _selectedClass!
                          : kReportClassFilterAll;
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
                        onChanged: usesClassAndMode
                            ? (v) => setState(
                                  () => _selectedClass =
                                      v ?? kReportClassFilterAll,
                                )
                            : null,
                      );
                    },
                    loading: () => DropdownButtonFormField<String>(
                      initialValue: _selectedClass ?? kReportClassFilterAll,
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
                          value: _selectedClass ?? kReportClassFilterAll,
                          child: Text(_selectedClass ?? kReportClassFilterAll),
                        ),
                      ],
                      onChanged: null,
                    ),
                    error: (_, __) => DropdownButtonFormField<String>(
                      initialValue: _selectedClass ?? kReportClassFilterAll,
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
                          value: _selectedClass ?? kReportClassFilterAll,
                          child: Text(_selectedClass ?? kReportClassFilterAll),
                        ),
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
                      final auth = ref.watch(authStateProvider).valueOrNull;
                      final canManageSession = auth is Authenticated &&
                          RolePermissions.canManageAcademicSession(auth.role);
                      final currentSessionAsync =
                          ref.watch(currentAcademicSessionProvider);
                      final currentSession = currentSessionAsync.valueOrNull;

                      // Non-admins always work in the current academic session; show it read-only.
                      if (!canManageSession) {
                        final effective = currentSession ??
                            _selectedSession ??
                            _defaultReportSession();
                        if (effective != _selectedSession) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() => _selectedSession = effective);
                            }
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
                          child: Text(effective),
                        );
                      }

                      final sessionOptionsAsync =
                          ref.watch(academicSessionOptionsProvider);
                      return sessionOptionsAsync.when(
                        data: (options) {
                          final list = options.isNotEmpty
                              ? options
                              : [_defaultReportSession()];
                          final value = _selectedSession != null &&
                                  list.contains(_selectedSession)
                              ? _selectedSession!
                              : list.first;
                          if (_selectedSession == null ||
                              !list.contains(_selectedSession!)) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted) {
                                setState(() => _selectedSession = list.first);
                              }
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
                                .map(
                                  (s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(s),
                                  ),
                                )
                                .toList(),
                            onChanged: usesSession
                                ? (v) => setState(() => _selectedSession = v)
                                : null,
                          );
                        },
                        loading: () => DropdownButtonFormField<String>(
                          initialValue:
                              _selectedSession ?? _defaultReportSession(),
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
                              value:
                                  _selectedSession ?? _defaultReportSession(),
                              child: Text(
                                _selectedSession ?? _defaultReportSession(),
                              ),
                            ),
                          ],
                          onChanged: null,
                        ),
                        error: (_, __) => DropdownButtonFormField<String>(
                          initialValue:
                              _selectedSession ?? _defaultReportSession(),
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
                              value:
                                  _selectedSession ?? _defaultReportSession(),
                              child: Text(
                                _selectedSession ?? _defaultReportSession(),
                              ),
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
                  _buildModeField(colorScheme, enabled: usesClassAndMode),
                  if (usesDateRange) ...[
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
      color: Colors.transparent,
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

  /// Live row count for the current report type + filters (same sources as export).
  AsyncValue<int> _watchExportRowCount() {
    switch (_selectedReportType) {
      case ReportType.studentSummary:
        return ref.watch(reportDataProvider(_filters)).whenData((r) => r.length);
      case ReportType.cohortSummary:
        return ref.watch(cohortReportDataProvider).whenData((r) => r.length);
      case ReportType.students:
        return ref
            .watch(studentsReportDataProvider(_filters))
            .whenData((r) => r.length);
      case ReportType.subjects:
        return ref
            .watch(subjectsReportDataProvider(_filters))
            .whenData((r) => r.length);
      case ReportType.attendance:
        return ref
            .watch(attendanceReportDataProvider(_filters))
            .whenData((r) => r.length);
      case ReportType.ministryHours:
        return ref
            .watch(ministryReportDataProvider(_filters))
            .whenData((r) => r.length);
      case ReportType.tests:
        return ref
            .watch(testsReportDataProvider(_filters))
            .whenData((r) => r.length);
      case ReportType.payments:
        return ref
            .watch(paymentsReportDataProvider(_filters))
            .whenData((r) => r.length);
      case ReportType.missionsPayment:
        return ref
            .watch(missionPaymentsReportDataProvider(_filters))
            .whenData((r) => r.length);
      case ReportType.missionLocations:
        return ref
            .watch(missionLocationsReportDataProvider)
            .whenData((r) => r.length);
    }
  }

  Widget _buildRightPanel(
    ColorScheme colorScheme,
    Color redColor,
    bool isDark,
    String dateRangeStr,
  ) {
    final isPdf = _reportFormat == ReportFormat.pdf;
    final typeLabel = _selectedReportType.label;
    final previewTitle = isPdf ? '$typeLabel PDF Preview' : '$typeLabel Report Preview';
    final usesDateRange = _usesDateRange(_selectedReportType);
    final previewBody = usesDateRange
        ? 'This ${isPdf ? 'PDF summary' : 'report'} includes data for the selected period ($dateRangeStr).'
        : 'This ${isPdf ? 'PDF summary' : 'report'} exports the current dataset for $typeLabel.';
    final rowCountAsync = _watchExportRowCount();

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
              previewBody,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial',
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            rowCountAsync.when(
              data: (n) => Text(
                '$n row${n == 1 ? '' : 's'} will be exported',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
              loading: () => Text(
                'Counting rows…',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
              error: (e, _) => Text(
                'Could not count rows: $e',
                style: TextStyle(
                  color: colorScheme.error,
                  fontSize: 13,
                  fontFamily: 'Questrial',
                ),
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
