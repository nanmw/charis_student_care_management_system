import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/core/utils/file_export_utils.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/student_repository.dart';
import 'package:charis_student_care/data/services/report_service.dart';
import 'package:charis_student_care/data/services/student_import_service.dart';
import 'package:charis_student_care/domain/use_cases/sort_students_alphabetically.dart';
import 'package:charis_student_care/presentation/providers/academic_session_providers.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/repository_providers.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/theme/app_table_style.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:charis_student_care/presentation/widgets/student_form_dialog.dart';
import 'package:charis_student_care/presentation/widgets/student_summary_dialog.dart';

/// Main content for Students List (shell provides header/sidebar/footer).
class StudentListScreen extends ConsumerStatefulWidget {
  const StudentListScreen({super.key});

  @override
  ConsumerState<StudentListScreen> createState() => _StudentListScreenState();
}

class _StudentListScreenState extends ConsumerState<StudentListScreen> {
  String? _statusFilter = 'Active';
  int? _classFilter;
  String? _modeFilter = 'Full-time';
  bool _defaultClassScheduled = false;
  String _searchQuery = '';
  int _displayedCount = 20; // Initial batch size
  bool _isLoadingMore = false;
  StudentDataSource? _dataSource;
  final ScrollController _scrollController = ScrollController();
  final StudentImportService _studentImportService =
      const StudentImportService();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMore();
    }
  }

  void _loadMore() {
    if (_isLoadingMore) return;
    setState(() {
      _isLoadingMore = true;
      _displayedCount += 20; // Load next batch
      _isLoadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final studentsAsync = ref.watch(studentsStreamProvider(_statusFilter));
    final classesAsync = ref.watch(classesVisibleToCurrentUserProvider);
    final classes = classesAsync.valueOrNull ?? [];
    final classIdToName = {for (final SchoolClass c in classes) c.id: c.name};
    final auth = ref.watch(authStateProvider).valueOrNull;
    final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
    if (auth is Authenticated &&
        classes.isNotEmpty &&
        !_defaultClassScheduled &&
        _classFilter == null) {
      _defaultClassScheduled = true;
      final scope = scopeAsync.valueOrNull;
      int defaultClassId;
      String? defaultMode;
      if (auth.role == UserRole.facilitator &&
          scope != null &&
          scope.classIds != null &&
          scope.classIds!.isNotEmpty) {
        defaultClassId = scope.classIds!.first;
        defaultMode = scope.mode ?? 'Full-time';
      } else {
        final year1 = classes.where((SchoolClass c) => c.name == 'Year 1');
        final firstClass = classes.first;
        defaultClassId = year1.isEmpty ? firstClass.id : year1.first.id;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _classFilter = defaultClassId;
          if (defaultMode != null) _modeFilter = defaultMode;
        });
      });
    }

    final modeOptions = ref.watch(modeOptionsForCurrentUserProvider);
    if (modeOptions.length == 1 && _modeFilter != modeOptions[0]) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _modeFilter = modeOptions[0]);
      });
    }

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Students List',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  fontFamily: 'Questrial',
                ),
              ),
              Row(
                children: [
                  RoleGuard(
                    canShow: RolePermissions.canExportReports,
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/reports?type=students'),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Export'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RoleGuard(
                    canShow: RolePermissions.canManageStudents,
                    child: ElevatedButton.icon(
                      onPressed: () => _openAddStudent(context),
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Add Student'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: redColor,
                        foregroundColor: AppColors.charisWhite,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12,),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RoleGuard(
                    canShow: RolePermissions.canManageStudents,
                    child: OutlinedButton.icon(
                      onPressed: () => _downloadStudentTemplate(context),
                      icon: const Icon(Icons.description_outlined, size: 20),
                      label: const Text('Download Template'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RoleGuard(
                    canShow: RolePermissions.canManageStudents,
                    child: OutlinedButton.icon(
                      onPressed: () => _importStudents(context),
                      icon: const Icon(Icons.upload_file_outlined, size: 20),
                      label: const Text('Import Students'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  RoleGuard(
                    canShow: RolePermissions.canManageStudents,
                    child: OutlinedButton.icon(
                      onPressed: () => _handleBulkTickHandbook(context, ref),
                      icon: const Icon(Icons.check_circle_outline, size: 20),
                      label: const Text('Tick All Handbook'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: redColor,
                        side: BorderSide(color: redColor),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12,),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _buildSearchField(),
              const SizedBox(width: 12),
              _buildClassDropdown(classes),
              const SizedBox(width: 12),
              _buildModeDropdown(),
              const SizedBox(width: 12),
              _buildFilterButton(),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: studentsAsync.when(
              data: (students) {
                final sorted = sortStudentsAlphabetically(students);
                var filtered = _searchQuery.isEmpty
                    ? sorted
                    : sorted.where((s) {
                        final q = _searchQuery.toLowerCase();
                        return s.surname.toLowerCase().contains(q) ||
                            s.firstName.toLowerCase().contains(q) ||
                            (s.email?.toLowerCase().contains(q) ?? false) ||
                            (s.contactInfo?.toLowerCase().contains(q) ?? false);
                      }).toList();
                if (_classFilter != null) {
                  filtered =
                      filtered.where((s) => s.classId == _classFilter).toList();
                }
                if (_modeFilter != null) {
                  filtered =
                      filtered.where((s) => s.mode == _modeFilter).toList();
                }
                final total = filtered.length;
                // Reset displayed count when filters change
                if (_displayedCount > total) {
                  _displayedCount = total;
                }
                final displayedStudents = total == 0
                    ? <Student>[]
                    : filtered.sublist(0, _displayedCount.clamp(0, total));
                _dataSource ??= StudentDataSource(
                  students: displayedStudents,
                  colorScheme: colorScheme,
                  redColor: redColor,
                  classIdToName: classIdToName,
                  onView: (s) =>
                      StudentSummaryDialog.show(context: context, student: s),
                  onEdit: (s) => _openEditStudent(context, s, ref),
                  onWithdraw: (s) => _applyStatus(context, ref, s, 'Withdrawn'),
                  onTransfer: (s) =>
                      _applyStatus(context, ref, s, 'Transferred'),
                  onCorrespondence: (s) =>
                      _applyStatus(context, ref, s, 'Correspondence'),
                  canManage: RolePermissions.canManageStudents(
                    (ref.read(authStateProvider).valueOrNull as Authenticated?)
                            ?.role ??
                        UserRole.facilitator,
                  ),
                );
                _dataSource!.updateData(
                  displayedStudents,
                  colorScheme,
                  classIdToName,
                  (
                    (s) =>
                        StudentSummaryDialog.show(context: context, student: s),
                    (s) => _openEditStudent(context, s, ref),
                    (s) => _applyStatus(context, ref, s, 'Withdrawn'),
                    (s) =>
                        _applyStatus(context, ref, s, 'Transferred'),
                    (s) => _applyStatus(context, ref, s, 'Correspondence'),
                    RolePermissions.canManageStudents(
                      (ref.read(authStateProvider).valueOrNull
                                  as Authenticated?)
                              ?.role ??
                          UserRole.facilitator,
                    ),
                  ),
                );
                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification) {
                      final metrics = notification.metrics;
                      if (metrics.pixels >= metrics.maxScrollExtent * 0.8 &&
                          _displayedCount < total &&
                          !_isLoadingMore) {
                        _loadMore();
                      }
                    }
                    return false;
                  },
                  child: RepaintBoundary(
                    child: SfDataGrid(
                      source: _dataSource!,
                      columnWidthMode: ColumnWidthMode.fill,
                      rowHeight: AppTableStyle.dataGridRowHeight,
                      headerRowHeight: AppTableStyle.dataGridHeaderRowHeight,
                      gridLinesVisibility: GridLinesVisibility.both,
                      headerGridLinesVisibility: GridLinesVisibility.both,
                      columns: [
                        GridColumn(
                            columnName: 'sn',
                            label: _header(context, 'S/N'),
                            width: 56,),
                        GridColumn(
                            columnName: 'surname',
                            label: _header(context, 'Surname'),
                            width: 120,),
                        GridColumn(
                            columnName: 'firstName',
                            label: _header(context, 'First Names'),
                            width: 120,),
                        GridColumn(
                            columnName: 'year',
                            label: _header(context, 'Year'),
                            width: 80,),
                        GridColumn(
                            columnName: 'mode',
                            label: _header(context, 'Mode'),
                            width: 90,),
                        GridColumn(
                            columnName: 'status',
                            label: _header(context, 'Status'),
                            width: 100,),
                        GridColumn(
                            columnName: 'contactInfo',
                            label: _header(context, 'Phone'),
                            width: 120,),
                        GridColumn(
                            columnName: 'email',
                            label: _header(context, 'Email'),
                            width: 140,),
                        GridColumn(
                            columnName: 'handbook',
                            label: _header(context, 'Handbook'),
                            width: 100,),
                        GridColumn(
                            columnName: 'mediaRelease',
                            label: _header(context, 'Media Release'),
                            width: 130,),
                        GridColumn(
                            columnName: 'accidentWaiver',
                            label: _header(context, 'Accident Waiver'),
                            width: 140,),
                        GridColumn(
                            columnName: 'actions',
                            label: _header(context, 'Actions'),
                            width: 140,),
                      ],
                    ),
                  ),
                );
              },
              loading: () => Center(
                  child:
                      CircularProgressIndicator(color: colorScheme.onSurface),),
              error: (err, _) => Center(
                  child: Text('Error: $err',
                      style: TextStyle(color: colorScheme.onSurface),),),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String text) {
    return AppTableStyle.sfHeaderCell(
      context,
      text,
      compactLineHeight: true,
    );
  }

  Widget _buildSearchField() {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 260,
      child: TextField(
        onChanged: (v) => setState(() {
          _searchQuery = v;
          _displayedCount = 20; // Reset to initial batch
        }),
        decoration: InputDecoration(
          hintText: 'Search students...',
          hintStyle:
              TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
          prefixIcon:
              Icon(Icons.search, color: colorScheme.onSurfaceVariant, size: 22),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
      ),
    );
  }

  Widget _buildFilterButton() {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: Builder(
        builder: (buttonContext) => OutlinedButton.icon(
          onPressed: () => _showFilterMenu(buttonContext),
          icon: const Icon(Icons.filter_list, size: 20),
          label: const Text('Filter', style: TextStyle(fontSize: 14)),
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.onSurfaceVariant,
            side: BorderSide(color: colorScheme.outlineVariant),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }

  Widget _buildClassDropdown(List<SchoolClass> classes) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 140,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: DropdownButton<int?>(
          value: classes.isEmpty ? null : _classFilter,
          hint: const Text('Class', style: TextStyle(fontSize: 14)),
          isExpanded: true,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(8),
          items: classes
              .map((c) => DropdownMenuItem<int?>(
                  value: c.id,
                  child: Text(c.name, style: const TextStyle(fontSize: 14)),),)
              .toList(),
          onChanged: (v) => setState(() {
            _classFilter = v;
            _displayedCount = 20;
          }),
        ),
      ),
    );
  }

  Widget _buildModeDropdown() {
    final colorScheme = Theme.of(context).colorScheme;
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
          hint: Text('Mode',
              style:
                  TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),),
          isExpanded: true,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(8),
          items: modeOptions
              .map(
                (v) => DropdownMenuItem<String?>(
                  value: v,
                  child: Text(
                    v,
                    style:
                        TextStyle(color: colorScheme.onSurface, fontSize: 14),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() {
            _modeFilter = v;
            _displayedCount = 20; // Reset to initial batch
          }),
        ),
      ),
    );
  }

  Future<void> _downloadStudentTemplate(BuildContext context) async {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated ||
        !RolePermissions.canManageStudents(auth.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to download the template'),
        ),
      );
      return;
    }
    try {
      const headers = [
        'surname',
        'firstName',
        'status',
        'className',
        'mode',
        'admissionYear',
        'contactInfo',
        'email',
        'handbook',
        'mediaRelease',
        'accidentWaiver',
        'academicSession',
      ];
      const exampleRow = [
        'Doe',
        'John',
        'Active',
        'Year 1',
        'Full-time',
        '2024',
        '0123456789',
        'john.doe@example.com',
        'true',
        'false',
        'false',
        '2026',
      ];
      final Uint8List bytes = ReportService.buildTableExcel(
        'Student Import Template',
        'Student Import Template',
        headers,
        [exampleRow],
      );

      final downloadsDir = await getDownloadsDirectory();
      const extension = 'xlsx';
      const suggestedName = 'Student_Import_Template.$extension';

      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save student import template',
        fileName: suggestedName,
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const [extension],
        initialDirectory: downloadsDir?.path,
      );
      if (path == null || path.isEmpty) return;

      var filePath = path;
      if (!filePath.toLowerCase().endsWith('.$extension')) {
        filePath = '$filePath.$extension';
      }
      try {
        await File(filePath).writeAsBytes(bytes, flush: true);
      } catch (writeError) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                FileExportUtils.userFacingSaveError(
                  writeError,
                  itemLabel: 'template',
                ),
              ),
              backgroundColor: Theme.of(context).colorScheme.error,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 8),
            ),
          );
        }
        return;
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Template saved to $filePath'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        final message = e is FileSystemException ||
                e.toString().toLowerCase().contains('pathaccess') ||
                e.toString().toLowerCase().contains('errno =')
            ? FileExportUtils.userFacingSaveError(e, itemLabel: 'template')
            : 'Could not save template. Please try again.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  Future<void> _importStudents(BuildContext context) async {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated ||
        !RolePermissions.canManageStudents(auth.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to import students'),
        ),
      );
      return;
    }

    bool progressShown = false;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final file = result.files.single;
      Uint8List? bytes = file.bytes;
      if (bytes == null) {
        final path = file.path;
        if (path == null || path.isEmpty) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not read selected file'),
              ),
            );
          }
          return;
        }
        bytes = await File(path).readAsBytes();
      }

      final parsed = _studentImportService.parseWorkbook(bytes);
      final preflightWarnings = <String>[...parsed.issues];
      final repo = ref.read(studentRepositoryProvider);

      final classes = await ref.read(classRepositoryProvider).getAllClasses();
      final classNameToId = <String, int>{
        for (final c in classes) c.name.toLowerCase(): c.id,
      };

      final fallbackSessionCode =
          ref.read(currentAcademicSessionProvider).valueOrNull?.trim();

      for (final parsedRow in parsed.rows) {
        final className = parsedRow.className;
        if (className != null &&
            className.isNotEmpty &&
            classNameToId[className.toLowerCase()] == null) {
          preflightWarnings.add(
            'Row ${parsedRow.rowNumber}: unknown class "$className", leaving class empty.',
          );
        }

        final sessionToUse = parsedRow.sessionCode ?? fallbackSessionCode;
        if (parsedRow.sessionCode != null &&
            parsedRow.sessionCode!.trim().isNotEmpty) {
          final exists =
              await repo.academicSessionExists(parsedRow.sessionCode!);
          if (!exists) {
            preflightWarnings.add(
              'Row ${parsedRow.rowNumber}: unknown academic session "${parsedRow.sessionCode}", leaving session empty.',
            );
          }
        } else if (sessionToUse != null &&
            sessionToUse.isNotEmpty &&
            parsedRow.sessionCode == null) {
          final exists = await repo.academicSessionExists(sessionToUse);
          if (!exists) {
            preflightWarnings.add(
              'Row ${parsedRow.rowNumber}: current academic session "$sessionToUse" not found, leaving session empty.',
            );
          }
        }

        final dupes = await repo.findPotentialDuplicates(
          surname: parsedRow.surname,
          firstName: parsedRow.firstName,
          admissionYear: parsedRow.admissionYear,
        );
        if (dupes.isNotEmpty) {
          preflightWarnings.add(
            'Row ${parsedRow.rowNumber}: possible duplicate of existing student '
            '${parsedRow.surname}, ${parsedRow.firstName}.',
          );
        }
      }

      if (context.mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Import preflight'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Rows ready to import: ${parsed.rows.length}'),
                Text('Warnings: ${preflightWarnings.length}'),
                if (preflightWarnings.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Sample warnings:',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  for (final issue in preflightWarnings.take(5))
                    Text('• $issue', style: const TextStyle(fontSize: 13)),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (proceed != true) return;
      }

      final errors = <String>[...preflightWarnings];
      final batchItems = <StudentBatchImportItem>[];
      for (final parsedRow in parsed.rows) {
        int? classId;
        final className = parsedRow.className;
        if (className != null && className.isNotEmpty) {
          classId = classNameToId[className.toLowerCase()];
        }

        var applySession = true;
        String? sessionCode = parsedRow.sessionCode ?? fallbackSessionCode;
        if (sessionCode != null && sessionCode.trim().isNotEmpty) {
          final exists = await repo.academicSessionExists(sessionCode);
          if (!exists) {
            applySession = false;
            sessionCode = null;
          }
        } else {
          applySession = false;
          sessionCode = null;
        }

        batchItems.add(
          StudentBatchImportItem(
            surname: parsedRow.surname,
            firstName: parsedRow.firstName,
            status: parsedRow.status,
            classId: classId,
            mode: parsedRow.mode,
            admissionYear: parsedRow.admissionYear,
            contactInfo: parsedRow.contactInfo,
            email: parsedRow.email,
            handbook: parsedRow.handbook,
            mediaRelease: parsedRow.mediaRelease,
            accidentWaiver: parsedRow.accidentWaiver,
            sessionCode: sessionCode,
            applySession: applySession,
          ),
        );
      }

      if (context.mounted) {
        progressShown = true;
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return const AlertDialog(
              content: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Importing students...'),
                ],
              ),
            );
          },
        );
      }

      var imported = 0;
      var writeFailed = 0;
      try {
        imported = await repo.importStudentsBatch(
          items: batchItems,
          userRole: auth.role,
          userId: auth.user.id,
          userDisplayName: auth.user.displayName,
          screen: 'Students Import',
        );
      } catch (e) {
        writeFailed = batchItems.length;
        errors.add('Batch import failed and was rolled back: $e');
      }

      final skipped = parsed.issues
          .where((i) => i.contains('missing surname or firstName'))
          .length;
      final validationSkipped = preflightWarnings.length;

      if (context.mounted) {
        if (progressShown) {
          Navigator.of(context, rootNavigator: true).pop();
          progressShown = false;
        }
        final message = writeFailed > 0
            ? 'Import failed. No students were imported (rolled back).'
            : 'Import completed. Imported $imported'
                '${skipped > 0 ? ', skipped $skipped row${skipped == 1 ? '' : 's'}' : ''}.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
          ),
        );

        if (errors.isNotEmpty || writeFailed > 0) {
          final limitedErrors = errors.length > 10
              ? [...errors.take(10), '... and ${errors.length - 10} more']
              : errors;
          showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Import details'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      writeFailed > 0
                          ? 'Import rolled back. No rows saved.'
                          : 'Imported $imported.',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Warnings: $validationSkipped • Save failures: $writeFailed',
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (limitedErrors.isNotEmpty) ...[
                      const Text(
                        'Issues:',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      for (final err in limitedErrors)
                        Text(
                          '• $err',
                          style: const TextStyle(fontSize: 13),
                        ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        }
      }
    } on StudentImportException catch (e) {
      if (context.mounted) {
        final recommendation = switch (e.type) {
          StudentImportFailureType.fileParse =>
            'Use the Download Template file or re-save your workbook as standard .xlsx in Excel, then retry.',
          StudentImportFailureType.headerValidation =>
            'Ensure your file includes at least surname and firstName columns (template recommended).',
          StudentImportFailureType.worksheetValidation =>
            'Ensure the workbook has at least one sheet with a header row and at least one data row.',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${e.message} $recommendation'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (progressShown && context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  void _showFilterMenu(BuildContext buttonContext) {
    final box = buttonContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final overlay =
        Overlay.of(buttonContext).context.findRenderObject()! as RenderBox;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = box.localToGlobal(
      Offset(box.size.width, box.size.height),
      ancestor: overlay,
    );
    final position = RelativeRect.fromRect(
      Rect.fromPoints(topLeft, bottomRight),
      Offset.zero & overlay.size,
    );
    showMenu<String?>(
      context: buttonContext,
      position: position,
      items: const [
        PopupMenuItem(value: 'Active', child: Text('Active')),
        PopupMenuItem(value: 'Withdrawn', child: Text('Withdrawn')),
        PopupMenuItem(value: 'Transferred', child: Text('Transferred')),
        PopupMenuItem(value: 'Correspondence', child: Text('Correspondence')),
      ],
    ).then((v) {
      if (!mounted) return;
      setState(() {
        _statusFilter = v;
        _displayedCount = 20; // Reset to initial batch
      });
    });
  }

  void _openAddStudent(BuildContext context) {
    StudentFormDialog.showAdd(
      context: context,
      ref: ref,
      onSaved: () {},
    );
  }

  void _openEditStudent(BuildContext context, Student s, WidgetRef ref) {
    if (!RolePermissions.canManageStudents(
      (ref.read(authStateProvider).valueOrNull as Authenticated?)?.role ??
          UserRole.facilitator,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You do not have permission to edit students'),),
      );
      return;
    }
    StudentFormDialog.showEdit(
        context: context, ref: ref, student: s, onSaved: () {},);
  }

  Future<void> _applyStatus(
      BuildContext context, WidgetRef ref, Student s, String newStatus,) async {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return;
    try {
      await ref.read(studentRepositoryProvider).updateStudent(
            s.id,
            status: newStatus,
            userRole: auth.role,
            userId: auth.user.id,
            userDisplayName: auth.user.displayName,
            screen: 'Students',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Status set to $newStatus')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _handleBulkTickHandbook(
      BuildContext context, WidgetRef ref,) async {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You must be logged in to perform this action'),),
      );
      return;
    }

    if (!RolePermissions.canManageStudents(auth.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('You do not have permission to perform this action'),),
      );
      return;
    }

    // Get current filtered students from the stream
    final studentsAsync = ref.read(studentsStreamProvider(_statusFilter));
    final students = studentsAsync.when(
      data: (students) => students,
      loading: () => <Student>[],
      error: (_, __) => <Student>[],
    );

    // Apply filters
    final sorted = sortStudentsAlphabetically(students);
    var filtered = _searchQuery.isEmpty
        ? sorted
        : sorted.where((s) {
            final q = _searchQuery.toLowerCase();
            return s.surname.toLowerCase().contains(q) ||
                s.firstName.toLowerCase().contains(q) ||
                (s.email?.toLowerCase().contains(q) ?? false) ||
                (s.contactInfo?.toLowerCase().contains(q) ?? false);
          }).toList();
    if (_classFilter != null) {
      filtered = filtered.where((s) => s.classId == _classFilter).toList();
    }
    if (_modeFilter != null) {
      filtered = filtered.where((s) => s.mode == _modeFilter).toList();
    }

    // Filter to only students with handbook=false
    final studentsToUpdate = filtered.where((s) => !s.handbook).toList();

    if (studentsToUpdate.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('All filtered students already have handbook ticked'),),
        );
      }
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(
          'Tick All Handbook',
          style:
              TextStyle(fontFamily: 'Questrial', fontWeight: FontWeight.w600),
        ),
        content: Text(
          'This will tick the handbook checkbox for ${studentsToUpdate.length} student${studentsToUpdate.length == 1 ? '' : 's'}.\n\nDo you want to continue?',
          style: const TextStyle(fontFamily: 'Questrial'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFamily: 'Questrial',
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: redColor,
              foregroundColor: AppColors.charisWhite,
            ),
            child: const Text(
              'Confirm',
              style: TextStyle(fontFamily: 'Questrial'),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Perform bulk update
    try {
      final studentIds = studentsToUpdate.map((s) => s.id).toList();
      final count =
          await ref.read(studentRepositoryProvider).bulkUpdateHandbook(
                studentIds: studentIds,
                userRole: auth.role,
                userId: auth.user.id,
                userDisplayName: auth.user.displayName,
                screen: 'Students',
              );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Handbook ticked for $count student${count == 1 ? '' : 's'}',),
            backgroundColor: redColor,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }
}

class StudentDataSource extends DataGridSource {
  StudentDataSource({
    required List<Student> students,
    required ColorScheme colorScheme,
    required Color redColor,
    Map<int, String> classIdToName = const {},
    required void Function(Student) onView,
    required void Function(Student) onEdit,
    required void Function(Student) onWithdraw,
    required void Function(Student) onTransfer,
    required void Function(Student) onCorrespondence,
    required bool canManage,
  })  : _students = students,
        _colorScheme = colorScheme,
        _redColor = redColor,
        _classIdToName = classIdToName,
        _onView = onView,
        _onEdit = onEdit,
        _onWithdraw = onWithdraw,
        _onTransfer = onTransfer,
        _onCorrespondence = onCorrespondence,
        _canManage = canManage {
    _buildRows();
  }

  List<Student> _students;
  ColorScheme _colorScheme;
  final Color _redColor;
  Map<int, String> _classIdToName;
  void Function(Student) _onView;
  void Function(Student) _onEdit;
  void Function(Student) _onWithdraw;
  void Function(Student) _onTransfer;
  void Function(Student) _onCorrespondence;
  bool _canManage;

  List<DataGridRow> _dataGridRows = [];

  void updateData(
    List<Student> students,
    ColorScheme colorScheme,
    Map<int, String> classIdToName,
    (
      void Function(Student),
      void Function(Student),
      void Function(Student),
      void Function(Student),
      void Function(Student),
      bool
    ) callbacks,
  ) {
    _students = students;
    _colorScheme = colorScheme;
    _classIdToName = classIdToName;
    _onView = callbacks.$1;
    _onEdit = callbacks.$2;
    _onWithdraw = callbacks.$3;
    _onTransfer = callbacks.$4;
    _onCorrespondence = callbacks.$5;
    _canManage = callbacks.$6;
    _buildRows();
    notifyListeners();
  }

  void _buildRows() {
    _dataGridRows = _students.asMap().entries.map((e) {
      final s = e.value;
      final yearLabel =
          s.classId != null ? (_classIdToName[s.classId] ?? '—') : '—';
      return DataGridRow(
        cells: [
          DataGridCell<int>(columnName: 'sn', value: e.key + 1),
          DataGridCell<String>(columnName: 'surname', value: s.surname),
          DataGridCell<String>(columnName: 'firstName', value: s.firstName),
          DataGridCell<String>(columnName: 'year', value: yearLabel),
          DataGridCell<String>(columnName: 'mode', value: s.mode ?? ''),
          DataGridCell<String>(columnName: 'status', value: s.status),
          DataGridCell<String>(
              columnName: 'contactInfo', value: s.contactInfo ?? '',),
          DataGridCell<String>(columnName: 'email', value: s.email ?? ''),
          DataGridCell<bool>(columnName: 'handbook', value: s.handbook),
          DataGridCell<bool>(columnName: 'mediaRelease', value: s.mediaRelease),
          DataGridCell<bool>(
              columnName: 'accidentWaiver', value: s.accidentWaiver,),
          DataGridCell<Student>(columnName: 'actions', value: s),
        ],
      );
    }).toList();
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter? buildRow(DataGridRow row) {
    final cells = row.getCells();
    final student =
        cells.firstWhere((c) => c.columnName == 'actions').value as Student;
    return DataGridRowAdapter(
      color: _colorScheme.surface,
      cells: cells.map<Widget>((cell) {
        if (cell.columnName == 'actions') {
          return Container(
            alignment: Alignment.centerLeft,
            padding: AppTableStyle.cellPadding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                Tooltip(
                  message: 'View Summary',
                  child: IconButton(
                    onPressed: () => _onView(student),
                    icon: const Icon(Icons.visibility_outlined, size: 14),
                    color: _colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                if (_canManage) ...[
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Edit',
                    child: IconButton(
                      onPressed: () => _onEdit(student),
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      color: _colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert,
                        size: 14, color: _colorScheme.onSurfaceVariant,),
                    padding: const EdgeInsets.all(4),
                    iconSize: 14,
                    style: IconButton.styleFrom(
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onSelected: (value) {
                      switch (value) {
                        case 'withdraw':
                          _onWithdraw(student);
                          break;
                        case 'transfer':
                          _onTransfer(student);
                          break;
                        case 'correspondence':
                          _onCorrespondence(student);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'withdraw',
                        child: Row(
                          children: [
                            Icon(Icons.person_off_outlined,
                                size: 14, color: _colorScheme.error,),
                            const SizedBox(width: 8),
                            Text('Withdraw',
                                style: TextStyle(color: _colorScheme.error),),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'transfer',
                        child: Row(
                          children: [
                            Icon(Icons.swap_horiz,
                                size: 14, color: _colorScheme.onSurfaceVariant,),
                            const SizedBox(width: 8),
                            const Text('Transfer'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'correspondence',
                        child: Row(
                          children: [
                            Icon(Icons.email_outlined,
                                size: 14, color: _colorScheme.onSurfaceVariant,),
                            const SizedBox(width: 8),
                            const Text('Correspondence'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          );
        }
        if (cell.columnName == 'status' &&
            (cell.value?.toString() ?? '') == 'Withdrawn') {
          return Container(
            alignment: Alignment.centerLeft,
            padding: AppTableStyle.cellPadding,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.withdrawnStatusBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _redColor),
                  ),
                  child: Text(
                    'Withdrawn',
                    style: TextStyle(
                      color: _redColor,
                      fontSize: 13,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'Questrial',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          );
        }
        if (cell.columnName == 'status' &&
            (cell.value?.toString() ?? '') == 'Correspondence') {
          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 92),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.correspondenceStatusBackground,
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: AppColors.correspondenceStatusGreen),
                ),
                child: const Text(
                  'Correspondence',
                  style: TextStyle(
                    color: AppColors.correspondenceStatusGreen,
                    fontSize: 12,
                    height: 1.1,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'Questrial',
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          );
        }
        if (cell.columnName == 'handbook' ||
            cell.columnName == 'mediaRelease' ||
            cell.columnName == 'accidentWaiver') {
          final boolValue = cell.value as bool? ?? false;
          return Container(
            alignment: Alignment.centerLeft,
            padding: AppTableStyle.cellPadding,
            child: Icon(
              boolValue ? Icons.check_circle : Icons.circle_outlined,
              color: boolValue ? _redColor : _colorScheme.onSurfaceVariant,
              size: 14,
            ),
          );
        }
        return Container(
          alignment: Alignment.centerLeft,
          padding: AppTableStyle.cellPadding,
          child: Text(
            cell.value?.toString() ?? '',
            style: AppTableStyle.dataGridBodyTextStyle(_colorScheme),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
    );
  }
}
