import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/academic_session_repository.dart';
import 'package:charis_student_care/data/repositories/attendance_repository.dart';
import 'package:charis_student_care/domain/attendance/attendance_thresholds.dart';
import 'package:charis_student_care/domain/use_cases/sort_students_alphabetically.dart';
import 'package:charis_student_care/presentation/providers/academic_session_providers.dart';
import 'package:charis_student_care/presentation/providers/attendance_providers.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/settings_providers.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/theme/app_table_style.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:charis_student_care/presentation/widgets/student_summary_dialog.dart';

const double _kDayColumnWidth = 40;
const double _kDayHeaderHeight = 48;
/// Stacked month row + column header. SfDataGrid tap rowIndex includes these.
const int _kHeaderLineCount = 2;

String attendanceDayColumnName(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return 'd_$y-$m-$d';
}

DateTime? attendanceDayFromColumnName(String columnName) {
  if (!columnName.startsWith('d_')) return null;
  final parts = columnName.substring(2).split('-');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  return DateTime(y, m, d);
}

String attendanceCellKey(int studentId, DateTime date) {
  return '$studentId-${attendanceDayColumnName(date).substring(2)}';
}

bool attendanceSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// One register cell. [present] is null when unmarked (no row).
class AttendanceCellEdit {
  AttendanceCellEdit({
    this.present,
    this.notes = '',
  });

  bool? present;
  String notes;

  AttendanceCellEdit copy() =>
      AttendanceCellEdit(present: present, notes: notes);

  bool sameAs(AttendanceCellEdit other) =>
      present == other.present && notes.trim() == other.notes.trim();
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
  int _selectedTerm = termNumberForMonth(DateTime.now().month);

  final Map<String, AttendanceCellEdit> _edits = {};
  Map<String, AttendanceCellEdit> _original = {};
  String _rangeKey = '';

  final DataGridController _gridController = DataGridController();
  AttendanceRegisterDataSource? _dataSource;
  bool _didAutoScrollToday = false;
  bool _saving = false;

  @override
  void dispose() {
    _gridController.dispose();
    _dataSource?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final studentsAsync = ref.watch(studentsStreamProvider('Active'));
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

    final sessionCode =
        ref.watch(currentAcademicSessionProvider).valueOrNull?.trim();
    final yearStr = AcademicSessionRepository.yearFromSessionCode(sessionCode) ??
        DateTime.now().year.toString();
    final sessionYear = int.tryParse(yearStr) ?? DateTime.now().year;
    final termRange = termDateRange(sessionYear, _selectedTerm);
    final days = calendarDaysInRange(termRange.$1, termRange.$2);
    final attendanceAsync = ref.watch(
      attendanceForRangeProvider(AttendanceDateRange(termRange.$1, termRange.$2)),
    );
    final expectedDays = ref
            .watch(attendanceThresholdsByModeProvider)
            .valueOrNull
            ?.forMode(_selectedMode)
            .term ??
        (_selectedMode == 'Hybrid'
            ? AppConstants.attendanceExpectedDaysHybridPerTerm
            : AppConstants.attendanceExpectedDaysPerTerm);

    final allStudents = studentsAsync.valueOrNull;
    if (allStudents != null) {
      final filtered = allStudents
          .where((s) => s.mode == _selectedMode)
          .where((s) => _classFilter == null || s.classId == _classFilter)
          .toList();
      _syncOriginalIfNeeded(
        sortStudentsAlphabetically(filtered),
        days,
        attendanceAsync.valueOrNull ?? const [],
      );
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
                  'Attendance Register',
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
          _buildFiltersRow(colorScheme, redColor, days),
          const SizedBox(height: 16),
          Expanded(
            child: studentsAsync.when(
              data: (allStudents) {
                final filtered = allStudents
                    .where((s) => s.mode == _selectedMode)
                    .where((s) =>
                        _classFilter == null || s.classId == _classFilter,)
                    .toList();
                final students = sortStudentsAlphabetically(filtered);
                if (students.isEmpty) {
                  return Center(
                    child: Text(
                      'No students match the selected mode.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontFamily: 'Questrial',
                      ),
                    ),
                  );
                }
                return _buildRegisterGrid(
                  context,
                  colorScheme,
                  redColor,
                  students,
                  days,
                  expectedDays,
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

  void _syncOriginalIfNeeded(
    List<Student> students,
    List<DateTime> days,
    List<AttendanceData> rows,
  ) {
    final rangeKey =
        '${_selectedTerm}_${days.isEmpty ? '' : attendanceDayColumnName(days.first)}_${days.isEmpty ? '' : attendanceDayColumnName(days.last)}_${students.map((s) => s.id).join(',')}';
    final original = <String, AttendanceCellEdit>{};
    for (final r in rows) {
      original[attendanceCellKey(r.studentId, r.date)] = AttendanceCellEdit(
        present: r.present == 1,
        notes: r.notes ?? '',
      );
    }
    if (rangeKey != _rangeKey) {
      _rangeKey = rangeKey;
      _original = original;
      _edits.clear();
      _didAutoScrollToday = false;
      return;
    }
    _original = original;
    _edits.removeWhere((key, edit) {
      final orig = original[key] ?? AttendanceCellEdit();
      return edit.sameAs(orig);
    });
  }

  AttendanceCellEdit _effective(int studentId, DateTime date) {
    final key = attendanceCellKey(studentId, date);
    return _edits[key] ?? _original[key] ?? AttendanceCellEdit();
  }

  bool get _hasUnsavedChanges {
    for (final entry in _edits.entries) {
      final orig = _original[entry.key] ?? AttendanceCellEdit();
      if (!entry.value.sameAs(orig)) return true;
    }
    return false;
  }

  void _setCell(
    int studentId,
    DateTime date,
    void Function(AttendanceCellEdit) update,
  ) {
    final key = attendanceCellKey(studentId, date);
    final next = _effective(studentId, date).copy();
    update(next);
    setState(() {
      _edits[key] = next;
    });
    _dataSource?.refresh();
  }

  Widget _buildFiltersRow(
    ColorScheme colorScheme,
    Color redColor,
    List<DateTime> days,
  ) {
    final today = DateTime.now();
    final todayInTerm = days.any((d) => attendanceSameDay(d, today));
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
                  'Term:',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
                const SizedBox(width: 8),
                _buildTermToggle(colorScheme, redColor),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              onPressed: todayInTerm ? () => _scrollToToday(days) : null,
              icon: const Icon(Icons.today, size: 20),
              label: const Text(
                'Jump to today',
                style: TextStyle(
                  fontFamily: 'Questrial',
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: redColor,
                side: BorderSide(color: redColor),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),),
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: todayInTerm
                  ? () => _markDayPresent(DateTime(today.year, today.month, today.day))
                  : null,
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: const Text(
                'Mark today present',
                style: TextStyle(
                  fontFamily: 'Questrial',
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: redColor,
                side: BorderSide(color: redColor),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _saving || !_hasUnsavedChanges ? null : _save,
              icon: const Icon(Icons.save, size: 20, color: AppColors.charisWhite),
              label: const Text(
                'Save Changes',
                style: TextStyle(
                  color: AppColors.charisWhite,
                  fontFamily: 'Questrial',
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: redColor,
                disabledBackgroundColor: redColor.withValues(alpha: 0.4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),),
              ),
            ),
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
        setState(() => _selectedMode = modeOptions[index]);
      },
      children: modeOptions
          .map((l) => Text(
                l,
                style: const TextStyle(fontFamily: 'Questrial', fontSize: 14),
              ),)
          .toList(),
    );
  }

  Widget _buildTermToggle(ColorScheme colorScheme, Color redColor) {
    const terms = [1, 2, 3];
    return ToggleButtons(
      constraints: const BoxConstraints(minWidth: 84, minHeight: 44),
      borderRadius: BorderRadius.circular(8),
      fillColor: redColor,
      selectedColor: AppColors.charisWhite,
      color: colorScheme.onSurface,
      isSelected: terms.map((t) => t == _selectedTerm).toList(),
      onPressed: (index) {
        setState(() => _selectedTerm = terms[index]);
      },
      children: terms
          .map((t) => Text(
                'Term $t',
                style: const TextStyle(fontFamily: 'Questrial', fontSize: 14),
              ),)
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
          hint: Text(
            'Class',
            style:
                TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
          ),
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
            setState(() => _classFilter = v);
          },
        ),
      ),
    );
  }

  Widget _buildRegisterGrid(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    List<Student> students,
    List<DateTime> days,
    int expectedDays,
  ) {
    _dataSource ??= AttendanceRegisterDataSource(
      students: students,
      days: days,
      lookup: _effective,
      expectedDays: expectedDays,
      colorScheme: colorScheme,
      redColor: redColor,
      onPresentChanged: (studentId, date, present) {
        _setCell(studentId, date, (e) => e.present = present);
      },
      onEditNotes: _editNotes,
      onViewStudent: (student) {
        StudentSummaryDialog.show(context: context, student: student);
      },
    );
    _dataSource!.updateData(
      students: students,
      days: days,
      expectedDays: expectedDays,
      colorScheme: colorScheme,
      redColor: redColor,
      notify: false,
    );

    final today = DateTime.now();
    if (!_didAutoScrollToday &&
        days.any((d) => attendanceSameDay(d, today))) {
      _didAutoScrollToday = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToToday(days);
      });
    }

    final columns = <GridColumn>[
      GridColumn(
        columnName: 'sn',
        width: 50,
        label: _headerCell(context, colorScheme, 'S/N'),
      ),
      GridColumn(
        columnName: 'name',
        width: 180,
        label: _headerCell(context, colorScheme, 'Student Name'),
      ),
      ...days.map(
        (day) => GridColumn(
          columnName: attendanceDayColumnName(day),
          width: _kDayColumnWidth,
          label: _dayHeader(context, colorScheme, redColor, day),
        ),
      ),
      GridColumn(
        columnName: 'present',
        width: 88,
        label: _headerCell(context, colorScheme, 'Present'),
      ),
      GridColumn(
        columnName: 'pct',
        width: 72,
        label: _headerCell(context, colorScheme, '%'),
      ),
      GridColumn(
        columnName: 'view',
        width: 56,
        label: _headerCell(context, colorScheme, 'View'),
      ),
    ];

    return SfDataGrid(
      source: _dataSource!,
      controller: _gridController,
      columns: columns,
      frozenColumnsCount: 2,
      footerFrozenColumnsCount: 3,
      columnWidthMode: ColumnWidthMode.none,
      rowHeight: AppTableStyle.dataGridRowHeight,
      headerRowHeight: _kDayHeaderHeight,
      gridLinesVisibility: GridLinesVisibility.both,
      headerGridLinesVisibility: GridLinesVisibility.both,
      selectionMode: SelectionMode.none,
      navigationMode: GridNavigationMode.cell,
      isScrollbarAlwaysShown: true,
      stackedHeaderRows: [
        StackedHeaderRow(cells: _monthStackedCells(colorScheme, days)),
      ],
      onCellLongPress: (details) => _onNotesGesture(details, students),
      onCellSecondaryTap: (details) => _onNotesGesture(details, students),
    );
  }

  List<StackedHeaderCell> _monthStackedCells(
    ColorScheme colorScheme,
    List<DateTime> days,
  ) {
    final cells = <StackedHeaderCell>[
      StackedHeaderCell(
        columnNames: const ['sn', 'name'],
        child: const SizedBox.shrink(),
      ),
    ];
    var i = 0;
    while (i < days.length) {
      final month = days[i].month;
      final year = days[i].year;
      final names = <String>[];
      while (i < days.length &&
          days[i].month == month &&
          days[i].year == year) {
        names.add(attendanceDayColumnName(days[i]));
        i++;
      }
      cells.add(
        StackedHeaderCell(
          columnNames: names,
          child: Center(
            child: Text(
              DateFormat('MMMM').format(DateTime(year, month)),
              style: AppTableStyle.dataGridHeaderTextStyle(colorScheme),
            ),
          ),
        ),
      );
    }
    cells.add(
      StackedHeaderCell(
        columnNames: const ['present', 'pct', 'view'],
        child: const SizedBox.shrink(),
      ),
    );
    return cells;
  }

  Widget _headerCell(BuildContext context, ColorScheme colorScheme, String text) {
    return Container(
      padding: AppTableStyle.headerPadding,
      alignment: Alignment.centerLeft,
      color: Colors.transparent,
      child: Text(
        text,
        style: AppTableStyle.dataGridHeaderTextStyle(colorScheme),
        softWrap: false,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _dayHeader(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    DateTime day,
  ) {
    final isWeekend =
        day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
    final isToday = attendanceSameDay(day, DateTime.now());
    final weekday = DateFormat.E().format(day)[0];
    return Tooltip(
      message:
          '${DateFormat('EEE d MMM yyyy').format(day)} — click to mark all present',
      child: Material(
        color: isToday
            ? redColor.withValues(alpha: 0.22)
            : (isWeekend
                ? colorScheme.outlineVariant.withValues(alpha: 0.35)
                : Colors.transparent),
        child: InkWell(
          onTap: () => _markDayPresent(day),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${day.day}',
                  style: TextStyle(
                    color: isWeekend
                        ? colorScheme.onSurfaceVariant
                        : colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    height: 1.1,
                    fontFamily: 'Questrial',
                  ),
                ),
                Text(
                  weekday,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    height: 1.1,
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

  void _onNotesGesture(DataGridCellDetails details, List<Student> students) {
    final date = attendanceDayFromColumnName(details.column.columnName);
    if (date == null) return;
    final rowIndex = details.rowColumnIndex.rowIndex - _kHeaderLineCount;
    if (rowIndex < 0 || rowIndex >= students.length) return;
    _editNotes(students[rowIndex], date);
  }

  void _scrollToToday(List<DateTime> days) {
    final today = DateTime.now();
    final dayIndex = days.indexWhere((d) => attendanceSameDay(d, today));
    if (dayIndex < 0) return;
    _gridController.scrollToColumn(
      (2 + dayIndex).toDouble(),
      canAnimate: true,
      position: DataGridScrollPosition.center,
    );
  }

  Future<void> _markDayPresent(DateTime date) async {
    final allStudents = ref.read(studentsStreamProvider('Active')).valueOrNull;
    if (allStudents == null) return;
    final students = sortStudentsAlphabetically(
      allStudents
          .where((s) => s.mode == _selectedMode)
          .where((s) => _classFilter == null || s.classId == _classFilter)
          .toList(),
    );
    if (students.isEmpty) return;
    var count = 0;
    for (final student in students) {
      final current = _effective(student.id, date);
      if (current.present == true) continue;
      final key = attendanceCellKey(student.id, date);
      final next = current.copy()..present = true;
      _edits[key] = next;
      count++;
    }
    setState(() {});
    _dataSource?.refresh();
    if (!mounted || count == 0) {
      if (mounted && count == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('All filtered students are already marked present'),
          ),
        );
      }
      return;
    }
    final themeMode = ref.read(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Marked $count student${count == 1 ? '' : 's'} present for ${DateFormat('d MMM').format(date)}',
        ),
        backgroundColor: redColor,
      ),
    );
  }

  Future<void> _editNotes(Student student, DateTime date) async {
    final current = _effective(student.id, date);
    final controller = TextEditingController(text: current.notes);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Notes — ${student.surname} ${student.firstName}',
            style: const TextStyle(fontFamily: 'Questrial'),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  DateFormat('EEEE d MMMM yyyy').format(date),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontFamily: 'Questrial',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'Add notes...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (result == null) return;
    _setCell(student.id, date, (e) => e.notes = result);
  }

  Future<void> _save() async {
    final allStudents = await ref.read(studentsStreamProvider('Active').future);
    final students = sortStudentsAlphabetically(
      allStudents
          .where((s) => s.mode == _selectedMode)
          .where((s) => _classFilter == null || s.classId == _classFilter)
          .toList(),
    );
    final sessionCode =
        ref.read(currentAcademicSessionProvider).valueOrNull?.trim();
    final yearStr =
        AcademicSessionRepository.yearFromSessionCode(sessionCode) ??
            DateTime.now().year.toString();
    final sessionYear = int.tryParse(yearStr) ?? DateTime.now().year;
    final termRange = termDateRange(sessionYear, _selectedTerm);
    final days = calendarDaysInRange(termRange.$1, termRange.$2);

    final records = <AttendanceRecordEntry>[];
    for (final student in students) {
      for (final day in days) {
        final key = attendanceCellKey(student.id, day);
        final edit = _edits[key];
        if (edit == null) continue;
        final orig = _original[key] ?? AttendanceCellEdit();
        if (edit.sameAs(orig)) continue;
        if (edit.present == null && edit.notes.trim().isEmpty) continue;
        records.add(
          AttendanceRecordEntry(
            date: DateTime.utc(day.year, day.month, day.day),
            studentId: student.id,
            present: edit.present ?? false,
            notes: edit.notes.trim().isEmpty ? null : edit.notes.trim(),
          ),
        );
      }
    }

    if (records.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No changes to save.')),
        );
      }
      return;
    }

    setState(() => _saving = true);
    try {
      final auth = ref.read(authStateProvider).valueOrNull;
      final userId = auth is Authenticated ? auth.user.id : null;
      final userDisplayName =
          auth is Authenticated ? auth.user.displayName : null;
      int? academicSessionId;
      if (sessionCode != null && sessionCode.isNotEmpty) {
        academicSessionId = await ref
            .read(academicSessionRepositoryProvider)
            .getSessionIdByCode(sessionCode);
      }
      await ref.read(attendanceRepositoryProvider).upsertAttendanceRecords(
            records,
            userRole: auth is Authenticated ? auth.role : UserRole.facilitator,
            academicSessionId: academicSessionId,
            userId: userId,
            userDisplayName: userDisplayName,
            screen: 'Attendance',
          );
      for (final rec in records) {
        _original[attendanceCellKey(rec.studentId, rec.date)] =
            AttendanceCellEdit(
          present: rec.present,
          notes: rec.notes ?? '',
        );
      }
      _edits.removeWhere((key, edit) {
        final orig = _original[key] ?? AttendanceCellEdit();
        return edit.sameAs(orig);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance saved.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class AttendanceRegisterDataSource extends DataGridSource {
  AttendanceRegisterDataSource({
    required List<Student> students,
    required List<DateTime> days,
    required AttendanceCellEdit Function(int studentId, DateTime date) lookup,
    required int expectedDays,
    required ColorScheme colorScheme,
    required Color redColor,
    required void Function(int studentId, DateTime date, bool present)
        onPresentChanged,
    required void Function(Student student, DateTime date) onEditNotes,
    required void Function(Student student) onViewStudent,
  })  : _students = students,
        _days = days,
        _lookup = lookup,
        _expectedDays = expectedDays,
        _colorScheme = colorScheme,
        _redColor = redColor,
        _onPresentChanged = onPresentChanged,
        _onEditNotes = onEditNotes,
        _onViewStudent = onViewStudent {
    _buildRows();
  }

  List<Student> _students;
  List<DateTime> _days;
  final AttendanceCellEdit Function(int studentId, DateTime date) _lookup;
  int _expectedDays;
  ColorScheme _colorScheme;
  Color _redColor;
  final void Function(int studentId, DateTime date, bool present)
      _onPresentChanged;
  final void Function(Student student, DateTime date) _onEditNotes;
  final void Function(Student student) _onViewStudent;
  List<DataGridRow> _rows = [];

  void updateData({
    required List<Student> students,
    required List<DateTime> days,
    required int expectedDays,
    required ColorScheme colorScheme,
    required Color redColor,
    bool notify = true,
  }) {
    _students = students;
    _days = days;
    _expectedDays = expectedDays;
    _colorScheme = colorScheme;
    _redColor = redColor;
    _buildRows();
    if (notify) notifyListeners();
  }

  void refresh() {
    _buildRows();
    notifyListeners();
  }

  @override
  List<DataGridRow> get rows => _rows;

  void _buildRows() {
    _rows = _students.asMap().entries.map((entry) {
      final index = entry.key;
      final student = entry.value;
      final cells = <DataGridCell<dynamic>>[
        DataGridCell<int>(columnName: 'sn', value: index + 1),
        DataGridCell<String>(
          columnName: 'name',
          value: '${student.surname} ${student.firstName}',
        ),
      ];
      var presentCount = 0;
      for (final day in _days) {
        final cell = _lookup(student.id, day);
        if (cell.present == true) presentCount++;
        cells.add(
          DataGridCell<bool?>(
            columnName: attendanceDayColumnName(day),
            value: cell.present,
          ),
        );
      }
      cells.add(DataGridCell<int>(columnName: 'present', value: presentCount));
      cells.add(
        DataGridCell<String>(
          columnName: 'pct',
          value: _expectedDays <= 0
              ? '0%'
              : '${(presentCount / _expectedDays * 100).toStringAsFixed(0)}%',
        ),
      );
      cells.add(DataGridCell<int>(columnName: 'view', value: student.id));
      return DataGridRow(cells: cells);
    }).toList();
  }

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final index = _rows.indexOf(row);
    if (index < 0 || index >= _students.length) {
      return const DataGridRowAdapter(cells: []);
    }
    final student = _students[index];
    final today = DateTime.now();
    return DataGridRowAdapter(
      cells: row.getCells().map((cell) {
        if (cell.columnName == 'sn') {
          return _padded(
            Text(
              '${cell.value}',
              style: AppTableStyle.dataGridBodyTextStyle(_colorScheme),
            ),
          );
        }
        if (cell.columnName == 'name') {
          return _padded(
            Text(
              cell.value as String,
              style: AppTableStyle.dataGridBodyTextStyle(_colorScheme),
            ),
          );
        }
        if (cell.columnName == 'present') {
          final count = cell.value as int;
          return _padded(
            Text(
              '$count/$_expectedDays',
              style: AppTableStyle.dataGridBodyTextStyle(_colorScheme),
            ),
          );
        }
        if (cell.columnName == 'pct') {
          return _padded(
            Text(
              cell.value as String,
              style: AppTableStyle.dataGridBodyTextStyle(_colorScheme),
            ),
          );
        }
        if (cell.columnName == 'view') {
          return Center(
            child: IconButton(
              onPressed: () => _onViewStudent(student),
              icon: Icon(
                Icons.visibility_outlined,
                size: 14,
                color: _colorScheme.onSurfaceVariant,
              ),
              tooltip: 'View Student Summary',
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(),
            ),
          );
        }
        final date = attendanceDayFromColumnName(cell.columnName);
        if (date == null) {
          return const SizedBox.shrink();
        }
        final edit = _lookup(student.id, date);
        final isWeekend =
            date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
        final isToday = attendanceSameDay(date, today);
        final hasNotes = edit.notes.trim().isNotEmpty;
        return ColoredBox(
          color: isToday
              ? _redColor.withValues(alpha: 0.08)
              : (isWeekend
                  ? _colorScheme.outlineVariant.withValues(alpha: 0.18)
                  : Colors.transparent),
          child: Stack(
            children: [
              Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: FittedBox(
                    child: Checkbox(
                      value: edit.present == true,
                      onChanged: (v) =>
                          _onPresentChanged(student.id, date, v ?? false),
                      activeColor: _redColor,
                      checkColor: AppColors.charisWhite,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
              if (hasNotes)
                Positioned(
                  top: 0,
                  right: 0,
                  child: GestureDetector(
                    onTap: () => _onEditNotes(student, date),
                    child: Icon(
                      Icons.edit_note,
                      size: 12,
                      color: _redColor,
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _padded(Widget child) {
    return Container(
      padding: AppTableStyle.cellPadding,
      alignment: Alignment.centerLeft,
      child: child,
    );
  }
}
