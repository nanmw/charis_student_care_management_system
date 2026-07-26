import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:go_router/go_router.dart';
import 'package:charis_student_care/core/utils/date_utils.dart'
    as app_date_utils;
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/attendance_repository.dart';
import 'package:charis_student_care/domain/use_cases/sort_students_alphabetically.dart';
import 'package:charis_student_care/presentation/providers/attendance_providers.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/theme/app_table_style.dart';
import 'package:charis_student_care/presentation/widgets/attendance_date_picker_dialog.dart';
import 'package:charis_student_care/presentation/widgets/student_summary_dialog.dart';

// #region agent log (disabled for performance - synchronous file I/O was blocking UI)
void _debugLog(String location, String message, Map<String, dynamic> data,
    String hypothesisId,) {
  // No-op: was causing UI jank due to synchronous file writes on every attendance action.
}
// #endregion

/// One row's editable state for attendance form.
class _RowEdit {
  _RowEdit({
    required this.present,
    this.notes = '',
  });

  bool present;
  String notes;

  int get percent => present ? 100 : 0;
}

class AttendanceScreen extends ConsumerStatefulWidget {
  const AttendanceScreen({super.key});

  @override
  ConsumerState<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends ConsumerState<AttendanceScreen> {
  String _selectedMode = 'Full-time';
  int? _classFilter;
  bool _defaultClassScheduled = false;
  DateTime _attendanceDate = DateTime.now();
  Map<int, _RowEdit> _edits = {};
  Map<int, _RowEdit> _originalEdits = {};
  final Map<int, TextEditingController> _noteControllers = {};
  String _refillKey = '';
  int _displayedCount = 30; // Initial batch size
  bool _isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    for (final c in _noteControllers.values) {
      c.dispose();
    }
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
      _displayedCount += 30; // Load next batch
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
    final studentsAsync = ref.watch(studentsStreamProvider('Active'));
    final attendanceAsync =
        ref.watch(attendanceForDateProvider(_attendanceDate));
    final visibleClassesRaw =
        ref.watch(classesVisibleToCurrentUserProvider).valueOrNull;
    final visibleClasses = visibleClassesRaw ?? <SchoolClass>[];
    final scopeAsync = ref.watch(currentUserFacilitatorScopeProvider);
    final auth = ref.watch(authStateProvider).valueOrNull;
    if (auth is Authenticated &&
        visibleClasses.isNotEmpty &&
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
        final year1 =
            visibleClasses.where((SchoolClass c) => c.name == 'Year 1');
        defaultClassId =
            year1.isEmpty ? visibleClasses.first.id : year1.first.id;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _classFilter = defaultClassId;
          if (defaultMode != null) _selectedMode = defaultMode;
        });
      });
    }

    final modeOptions = ref.watch(modeOptionsForCurrentUserProvider);
    if (modeOptions.length == 1 && _selectedMode != modeOptions[0]) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedMode = modeOptions[0]);
      });
    }

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Attendance Entry',
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
                  onPressed: () => context.go('/reports?type=attendance'),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Export'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildFiltersRow(colorScheme, redColor),
          const SizedBox(height: 24),
          Expanded(
            child: studentsAsync.when(
              data: (allStudents) {
                final filtered = allStudents
                    .where((s) => s.mode == _selectedMode)
                    .where((s) =>
                        _classFilter == null || s.classId == _classFilter,)
                    .toList();
                final allStudentsSorted = sortStudentsAlphabetically(filtered);
                // Reset displayed count if filters changed
                final total = allStudentsSorted.length;
                if (_displayedCount > total) {
                  _displayedCount = total;
                }
                final displayedStudents = total == 0
                    ? <Student>[]
                    : allStudentsSorted.sublist(
                        0, _displayedCount.clamp(0, total),);
                // Initialize edits for all filtered students, but only create controllers for displayed ones
                _refillEditsIfNeeded(
                    allStudentsSorted, attendanceAsync.valueOrNull,
                    displayedStudents: displayedStudents,);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Daily Attendance Record',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        fontFamily: 'Questrial',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: allStudentsSorted.isEmpty
                          ? Center(
                              child: Text(
                                'No students match the selected mode.',
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                  fontFamily: 'Questrial',
                                ),
                              ),
                            )
                          : NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollUpdateNotification) {
                                  final metrics = notification.metrics;
                                  if (metrics.pixels >=
                                          metrics.maxScrollExtent * 0.8 &&
                                      _displayedCount < total &&
                                      !_isLoadingMore) {
                                    _loadMore();
                                  }
                                }
                                return false;
                              },
                              child: _buildTable(context, colorScheme, redColor,
                                  displayedStudents,),
                            ),
                    ),
                  ],
                );
              },
              loading: () => Center(
                child: CircularProgressIndicator(color: colorScheme.onSurface),
              ),
              error: (err, _) => Center(
                child: Text(
                  'Error: $err',
                  style: TextStyle(color: colorScheme.onSurface),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _refillEditsIfNeeded(List<Student> students, List<AttendanceData>? rows,
      {List<Student>? displayedStudents,}) {
    final key =
        '${_attendanceDate.millisecondsSinceEpoch}_${students.map((s) => s.id).join(",")}_${rows?.length ?? -1}';
    if (key == _refillKey) {
      // Still need to ensure controllers exist for displayed students
      final displayedIds =
          (displayedStudents ?? students).map((s) => s.id).toSet();
      for (final id in displayedIds) {
        final edit = _edits[id] ?? _RowEdit(present: false);
        _noteControllers[id] ??= TextEditingController(text: edit.notes);
      }
      // Clean up controllers for students no longer displayed
      for (final id in _noteControllers.keys.toList()) {
        if (!displayedIds.contains(id)) {
          _noteControllers[id]?.dispose();
          _noteControllers.remove(id);
        }
      }
      return;
    }
    _refillKey = key;
    final displayedIds =
        (displayedStudents ?? students).map((s) => s.id).toSet();
    // Clean up controllers for students no longer in displayed list
    for (final id in _noteControllers.keys.toList()) {
      if (!displayedIds.contains(id)) {
        _noteControllers[id]?.dispose();
        _noteControllers.remove(id);
      }
    }
    final rowMap = <int, AttendanceData>{};
    if (rows != null) {
      for (final r in rows) {
        rowMap[r.studentId] = r;
      }
    }
    final edits = <int, _RowEdit>{};
    final originalEdits = <int, _RowEdit>{};
    // Initialize edits for ALL students (for save functionality)
    for (final s in students) {
      final row = rowMap[s.id];
      // #region agent log
      _debugLog(
          'attendance_screen.dart:_refillEditsIfNeeded',
          'Processing student',
          {
            'studentId': s.id,
            'hasRow': row != null,
            'rowPresent': row?.present,
            'rowNotes': row?.notes,
          },
          'D',);
      // #endregion
      final notes = row?.notes ?? '';
      final originalEdit = _RowEdit(
        present: row?.present == 1,
        notes: notes,
      );
      originalEdits[s.id] = originalEdit;
      edits[s.id] = _RowEdit(
        present: row?.present == 1,
        notes: notes,
      );
    }
    // Only create controllers for displayed students
    for (final s in (displayedStudents ?? students)) {
      final edit = edits[s.id] ?? _RowEdit(present: false);
      final controller =
          _noteControllers[s.id] ??= TextEditingController(text: edit.notes);
      controller.text = edit.notes;
    }
    if (mounted) {
      setState(() {
        _originalEdits = originalEdits;
        _edits = edits;
      });
    }
  }

  Widget _buildFiltersRow(ColorScheme colorScheme, Color redColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  'Student Mode:',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
                const SizedBox(width: 8),
                _buildModeToggle(colorScheme, redColor),
                const SizedBox(width: 24),
                Text(
                  'Class:',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
                const SizedBox(width: 8),
                _buildClassDropdown(colorScheme),
                const SizedBox(width: 24),
                Text(
                  'Attendance Date:',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
                const SizedBox(width: 8),
                _buildDateField(colorScheme),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildBulkTickButton(colorScheme, redColor),
            const SizedBox(width: 12),
            _buildSaveButton(colorScheme, redColor),
          ],
        ),
      ],
    );
  }

  Widget _buildModeToggle(ColorScheme colorScheme, Color redColor) {
    final modeOptions = ref.watch(modeOptionsForCurrentUserProvider);
    if (modeOptions.length == 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: redColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: redColor),
        ),
        child: Text(
          modeOptions[0],
          style: TextStyle(
            fontFamily: 'Questrial',
            fontSize: 14,
            color: colorScheme.onSurface,
          ),
        ),
      );
    }
    return ToggleButtons(
      constraints: const BoxConstraints(minWidth: 90, minHeight: 44),
      borderRadius: BorderRadius.circular(8),
      fillColor: redColor,
      selectedColor: AppColors.charisWhite,
      color: colorScheme.onSurface,
      isSelected: modeOptions.map((m) => m == _selectedMode).toList(),
      onPressed: (index) {
        setState(() {
          _selectedMode = modeOptions[index];
          _displayedCount = 30; // Reset to initial batch
        });
      },
      children: modeOptions
          .map((l) => Text(l,
              style: const TextStyle(fontFamily: 'Questrial', fontSize: 14),),)
          .toList(),
    );
  }

  Widget _buildClassDropdown(ColorScheme colorScheme) {
    final classes =
        ref.watch(classesVisibleToCurrentUserProvider).valueOrNull ?? [];
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
        child: DropdownButton<int?>(
          value: classes.isEmpty ? null : _classFilter,
          hint: Text('Class',
              style:
                  TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),),
          isExpanded: true,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(8),
          items: classes
              .map<DropdownMenuItem<int?>>(
                (SchoolClass c) => DropdownMenuItem<int?>(
                  value: c.id,
                  child: Text(
                    c.name,
                    style:
                        TextStyle(color: colorScheme.onSurface, fontSize: 14),
                  ),
                ),
              )
              .toList(),
          onChanged: (v) {
            setState(() {
              _classFilter = v;
              _displayedCount = 30; // Reset to initial batch
            });
          },
        ),
      ),
    );
  }

  Widget _buildDateField(ColorScheme colorScheme) {
    return InkWell(
      onTap: () async {
        int? effectiveClassFilter = _classFilter;
        if (effectiveClassFilter == null) {
          final visibleClasses = await ref.read(
            classesVisibleToCurrentUserProvider.future,
          );
          final auth = await ref.read(authStateProvider.future);
          if (auth is Authenticated && visibleClasses.isNotEmpty) {
            final year1 =
                visibleClasses.where((SchoolClass c) => c.name == 'Year 1');
            final firstClass = visibleClasses.first;
            effectiveClassFilter = auth.role == UserRole.facilitator
                ? firstClass.id
                : (year1.isEmpty ? firstClass.id : year1.first.id);
          }
        }
        // Always compute dates with attendance fresh for the current class filter.
        ref.invalidate(datesWithAttendanceProvider(effectiveClassFilter));
        final datesWithAttendance = await ref.read(
          datesWithAttendanceProvider(effectiveClassFilter).future,
        );
        if (!mounted) return;
        bool sameDay(DateTime a, DateTime b) =>
            a.year == b.year && a.month == b.month && a.day == b.day;
        final initialDate =
            datesWithAttendance.any((d) => sameDay(d, _attendanceDate))
                ? _attendanceDate
                : (datesWithAttendance.isNotEmpty
                    ? datesWithAttendance.reduce((a, b) => a.isAfter(b) ? a : b)
                    : DateTime.now());
        await showDialog<void>(
          context: context,
          builder: (context) => AttendanceDatePickerDialog(
            initialDate: initialDate,
            datesWithAttendance: datesWithAttendance,
            onDateSelected: (date) {
              if (mounted) {
                setState(() {
                  _attendanceDate = date;
                  _displayedCount = 30;
                });
              }
            },
          ),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              app_date_utils.DateUtils.formatAttendanceDate(_attendanceDate),
              style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  fontFamily: 'Questrial',),
            ),
            const SizedBox(width: 8),
            Icon(Icons.calendar_today,
                size: 20, color: colorScheme.onSurfaceVariant,),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(BuildContext context, ColorScheme colorScheme,
      Color redColor, List<Student> students,) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth;
        return RepaintBoundary(
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: Table(
                  columnWidths: const {
                    0: FlexColumnWidth(0.5),
                    1: FlexColumnWidth(2),
                    2: FlexColumnWidth(0.6),
                    3: FlexColumnWidth(2),
                    4: FlexColumnWidth(0.5),
                    5: FlexColumnWidth(0.4),
                  },
                  border: AppTableStyle.materialTableBorder(colorScheme),
                  children: [
                    TableRow(
                      decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,),
                      children: [
                        _tableHeader(context, 'S/N'),
                        _tableHeader(context, 'Student Name'),
                        _tableHeader(context, 'Present'),
                        _tableHeader(context, 'Notes'),
                        _tableHeader(context, '%'),
                        _tableHeader(context, 'View'),
                      ],
                    ),
                    ...students.asMap().entries.map((e) {
                      final index = e.key;
                      final student = e.value;
                      final edit =
                          _edits[student.id] ?? _RowEdit(present: false);
                      // Ensure controller exists
                      // #region agent log
                      _debugLog(
                          'attendance_screen.dart:_buildTable',
                          'Checking controller for student',
                          {
                            'studentId': student.id,
                            'hasController':
                                _noteControllers.containsKey(student.id),
                          },
                          'B',);
                      // #endregion
                      _noteControllers[student.id] ??=
                          TextEditingController(text: edit.notes);
                      // #region agent log
                      _debugLog(
                          'attendance_screen.dart:_buildTable',
                          'Controller ensured',
                          {
                            'studentId': student.id,
                            'controllerIsNull':
                                _noteControllers[student.id] == null,
                          },
                          'B',);
                      // #endregion
                      final controller = _noteControllers[student.id]!;
                      return TableRow(
                        decoration: BoxDecoration(color: colorScheme.surface),
                        children: [
                          _cell(
                              context,
                              colorScheme,
                              Text('${index + 1}',
                                  style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontSize: 14,
                                      fontFamily: 'Questrial',),),),
                          _cell(
                              context,
                              colorScheme,
                              Text('${student.surname} ${student.firstName}',
                                  style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontSize: 14,
                                      fontFamily: 'Questrial',),),),
                          _checkboxCell(
                              context,
                              colorScheme,
                              redColor,
                              edit.present,
                              (v) => _updateEdit(
                                  student.id, (e) => e.present = v,),),
                          _cell(
                            context,
                            colorScheme,
                            TextField(
                              onChanged: (v) => _updateEdit(
                                student.id,
                                (e) => e.notes = v,
                                rebuild: false,
                              ),
                              controller: controller,
                              decoration: InputDecoration(
                                hintText: 'Add notes...',
                                hintStyle: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    fontSize: 13,),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                disabledBorder: InputBorder.none,
                                errorBorder: InputBorder.none,
                                focusedErrorBorder: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6,),
                                isDense: true,
                              ),
                              style: TextStyle(
                                  color: colorScheme.onSurface, fontSize: 13,),
                            ),
                          ),
                          _cell(
                              context,
                              colorScheme,
                              Text('${edit.percent}%',
                                  style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontSize: 14,
                                      fontFamily: 'Questrial',),),),
                          _cell(
                            context,
                            colorScheme,
                            Center(
                              child: IconButton(
                                onPressed: () {
                                  StudentSummaryDialog.show(
                                    context: context,
                                    student: student,
                                  );
                                },
                                icon: Icon(Icons.visibility_outlined,
                                    size: 14,
                                    color: colorScheme.onSurfaceVariant,),
                                tooltip: 'View Student Summary',
                                padding: const EdgeInsets.all(6),
                                constraints: const BoxConstraints(),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _updateEdit(
    int studentId,
    void Function(_RowEdit) update, {
    bool rebuild = true,
  }) {
    final e = _edits[studentId];
    if (e != null) {
      update(e);
      if (rebuild) setState(() {});
    }
  }

  Widget _tableHeader(BuildContext context, String text) {
    return AppTableStyle.sfHeaderCell(context, text);
  }

  Widget _cell(BuildContext context, ColorScheme colorScheme, Widget child) {
    return Padding(
      padding: AppTableStyle.cellPadding,
      child: child,
    );
  }

  Widget _checkboxCell(BuildContext context, ColorScheme colorScheme,
      Color redColor, bool value, ValueChanged<bool> onChanged,) {
    return Padding(
      padding: AppTableStyle.cellPadding,
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: FittedBox(
            fit: BoxFit.contain,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: redColor,
              checkColor: AppColors.charisWhite,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBulkTickButton(ColorScheme colorScheme, Color redColor) {
    return OutlinedButton.icon(
      onPressed: () => _handleBulkTickAttendance(context),
      icon: const Icon(Icons.check_circle_outline, size: 20),
      label: const Text('Tick All Present',
          style:
              TextStyle(fontFamily: 'Questrial', fontWeight: FontWeight.w600),),
      style: OutlinedButton.styleFrom(
        foregroundColor: redColor,
        side: BorderSide(color: redColor),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildSaveButton(ColorScheme colorScheme, Color redColor) {
    return ElevatedButton.icon(
      onPressed: _save,
      icon: const Icon(Icons.save, size: 20, color: AppColors.charisWhite),
      label: const Text('Save Changes',
          style: TextStyle(
              color: AppColors.charisWhite,
              fontFamily: 'Questrial',
              fontWeight: FontWeight.w600,),),
      style: ElevatedButton.styleFrom(
        backgroundColor: redColor,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _handleBulkTickAttendance(BuildContext context) async {
    final themeMode = ref.read(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    // Get current filtered students
    final studentsAsync = ref.read(studentsStreamProvider('Active'));
    final allStudents = studentsAsync.when(
      data: (students) => students,
      loading: () => <Student>[],
      error: (_, __) => <Student>[],
    );

    final filtered = allStudents
        .where((s) => s.mode == _selectedMode)
        .where((s) => _classFilter == null || s.classId == _classFilter)
        .toList();
    final students = sortStudentsAlphabetically(filtered);

    if (students.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No students match the selected filters'),),
        );
      }
      return;
    }

    // Filter to students who don't already have present=true
    final studentsToUpdate = students.where((s) {
      final edit = _edits[s.id];
      return edit == null || !edit.present;
    }).toList();

    if (studentsToUpdate.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('All filtered students are already marked as present'),),
        );
      }
      return;
    }

    // Update _edits map for all students to mark as present
    // Preserve existing notes
    for (final student in studentsToUpdate) {
      final existingEdit = _edits[student.id];
      if (existingEdit != null) {
        existingEdit.present = true;
      } else {
        _edits[student.id] = _RowEdit(
          present: true,
          notes: '',
        );
      }
    }

    // Update UI
    setState(() {});

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Marked ${studentsToUpdate.length} student${studentsToUpdate.length == 1 ? '' : 's'} as present',),
          backgroundColor: redColor,
        ),
      );
    }
  }

  Future<void> _save() async {
    // #region agent log
    _debugLog('attendance_screen.dart:_save', 'Save method called',
        {'date': _attendanceDate.toString(), 'editsCount': _edits.length}, 'E',);
    // #endregion
    final repo = ref.read(attendanceRepositoryProvider);
    // Use scoped students (facilitators see only their class)
    // #region agent log
    _debugLog(
        'attendance_screen.dart:_save', 'Getting students stream', {}, 'C',);
    // #endregion
    final allStudents = await ref.read(studentsStreamProvider('Active').future);
    // #region agent log
    _debugLog('attendance_screen.dart:_save', 'Got students from stream',
        {'count': allStudents.length}, 'C',);
    // #endregion

    final filtered = allStudents
        .where((s) => s.mode == _selectedMode)
        .where((s) => _classFilter == null || s.classId == _classFilter)
        .toList();
    final students = sortStudentsAlphabetically(filtered);
    // #region agent log
    _debugLog(
        'attendance_screen.dart:_save',
        'Filtered students',
        {
          'filteredCount': students.length,
          'selectedMode': _selectedMode,
          'classFilter': _classFilter,
        },
        'E',);
    // #endregion

    // Only include entries that have been changed from their original state
    final entries = <AttendanceEntry>[];
    for (final student in students) {
      final edit = _edits[student.id] ?? _RowEdit(present: false);
      final originalEdit = _originalEdits[student.id];

      // Check if this entry has changed
      bool hasChanged = false;

      if (originalEdit == null) {
        // New entry - include if present is true or notes are not empty
        if (edit.present || (edit.notes.trim().isNotEmpty)) {
          hasChanged = true;
        }
      } else {
        // Existing entry - check if present or notes changed
        final notesChanged = (edit.notes.trim()) != (originalEdit.notes.trim());
        final presentChanged = edit.present != originalEdit.present;

        if (presentChanged || notesChanged) {
          hasChanged = true;
        }
      }

      if (hasChanged) {
        entries.add(
          AttendanceEntry(
            studentId: student.id,
            present: edit.present,
            notes: edit.notes.trim().isEmpty ? null : edit.notes.trim(),
          ),
        );
      }
    }
    // #region agent log
    _debugLog(
        'attendance_screen.dart:_save',
        'Created entries',
        {'entriesCount': entries.length, 'totalStudents': students.length},
        'E',);
    // #endregion

    try {
      // Get userId for change set logging
      final auth = ref.read(authStateProvider).valueOrNull;
      final userId = auth is Authenticated ? auth.user.id : null;

      // #region agent log
      _debugLog(
          'attendance_screen.dart:_save',
          'Calling upsertAttendanceForDate',
          {'entriesCount': entries.length},
          'A',);
      // #endregion
      final userDisplayName =
          auth is Authenticated ? auth.user.displayName : null;
      await repo.upsertAttendanceForDate(
        _attendanceDate,
        entries,
        userRole: auth is Authenticated
            ? auth.role
            : UserRole.facilitator,
        userId: userId,
        userDisplayName: userDisplayName,
        screen: 'Attendance',
      );
      // #region agent log
      _debugLog('attendance_screen.dart:_save', 'Upsert completed successfully',
          {}, 'A',);
      // #endregion
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Attendance saved.')));
      }
    } catch (e, stackTrace) {
      // #region agent log
      _debugLog('attendance_screen.dart:_save', 'Error in save',
          {'error': e.toString(), 'stackTrace': stackTrace.toString()}, 'A',);
      // #endregion
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
