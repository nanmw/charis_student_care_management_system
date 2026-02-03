import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/core/utils/date_utils.dart' as app_date_utils;
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/attendance_repository.dart';
import 'package:charis_student_care/domain/use_cases/sort_students_alphabetically.dart';
import 'package:charis_student_care/presentation/providers/attendance_providers.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';

// #region agent log (disabled for performance - synchronous file I/O was blocking UI)
void _debugLog(String location, String message, Map<String, dynamic> data, String hypothesisId) {
  // No-op: was causing UI jank due to synchronous file writes on every attendance action.
}
// #endregion

/// Mode filter options (must match students.mode values).
const List<String> _modeOptions = ['Full-time', 'Hybrid'];

/// Academic year options for dropdown (Year 1-3 + All).
const List<String?> _academicYearOptions = [null, 'Year 1', 'Year 2', 'Year 3'];

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
  String? _academicYear;
  DateTime _attendanceDate = DateTime.now();
  Map<int, _RowEdit> _edits = {};
  final Map<int, TextEditingController> _noteControllers = {};
  String _refillKey = '';

  @override
  void dispose() {
    for (final c in _noteControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final studentsAsync = ref.watch(studentsStreamProvider('Active'));
    final attendanceAsync = ref.watch(attendanceForDateProvider(_attendanceDate));

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Attendance Entry',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 24,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 16),
          _buildFiltersRow(colorScheme),
          const SizedBox(height: 24),
          Expanded(
            child: studentsAsync.when(
              data: (allStudents) {
                final filtered = allStudents
                    .where((s) => s.mode == _selectedMode)
                    .where((s) => _academicYear == null || s.year == _academicYear)
                    .toList();
                final students = sortStudentsAlphabetically(filtered);
                _refillEditsIfNeeded(students, attendanceAsync.valueOrNull);
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
                      child: students.isEmpty
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
                          : _buildTable(context, colorScheme, students),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _buildSaveButton(colorScheme),
                    ),
                  ],
                );
              },
              loading: () => Center(
                  child: CircularProgressIndicator(color: colorScheme.onSurface)),
              error: (err, _) => Center(
                  child: Text('Error: $err',
                      style: TextStyle(color: colorScheme.onSurface))),
            ),
          ),
        ],
      ),
    );
  }

  void _refillEditsIfNeeded(List<Student> students, List<AttendanceData>? rows) {
    final key = '${_attendanceDate.millisecondsSinceEpoch}_${students.map((s) => s.id).join(",")}_${rows?.length ?? -1}';
    if (key == _refillKey) return;
    _refillKey = key;
    final studentIds = students.map((s) => s.id).toSet();
    for (final id in _noteControllers.keys.toList()) {
      if (!studentIds.contains(id)) {
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
    for (final s in students) {
      final row = rowMap[s.id];
      // #region agent log
      _debugLog('attendance_screen.dart:_refillEditsIfNeeded', 'Processing student', {'studentId': s.id, 'hasRow': row != null, 'rowPresent': row?.present, 'rowNotes': row?.notes}, 'D');
      // #endregion
      final notes = row?.notes ?? '';
      edits[s.id] = _RowEdit(
        present: row?.present == 1,
        notes: notes,
      );
      final controller = _noteControllers[s.id] ??= TextEditingController(text: notes);
      controller.text = notes;
    }
    if (mounted) setState(() => _edits = edits);
  }

  Widget _buildFiltersRow(ColorScheme colorScheme) {
    return Row(
      children: [
        Text('Student Mode:',
            style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial')),
        const SizedBox(width: 8),
        _buildModeToggle(colorScheme),
        const SizedBox(width: 24),
        Text('Academic Year:',
            style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial')),
        const SizedBox(width: 8),
        _buildAcademicYearDropdown(colorScheme),
        const SizedBox(width: 24),
        Text('Attendance Date:',
            style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial')),
        const SizedBox(width: 8),
        _buildDateField(colorScheme),
      ],
    );
  }

  Widget _buildModeToggle(ColorScheme colorScheme) {
    return ToggleButtons(
      constraints: const BoxConstraints(minWidth: 90, minHeight: 44),
      borderRadius: BorderRadius.circular(8),
      fillColor: AppColors.primaryActionRed,
      selectedColor: AppColors.charisWhite,
      color: colorScheme.onSurface,
      isSelected: _modeOptions.map((m) => m == _selectedMode).toList(),
      onPressed: (index) {
        setState(() => _selectedMode = _modeOptions[index]);
      },
      children: _modeOptions.map((l) => Text(l, style: const TextStyle(fontFamily: 'Questrial', fontSize: 14))).toList(),
    );
  }

  Widget _buildAcademicYearDropdown(ColorScheme colorScheme) {
    return SizedBox(
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
          value: _academicYear,
          hint: Text('All', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
          isExpanded: true,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(8),
          items: _academicYearOptions
              .map((y) => DropdownMenuItem<String?>(
                    value: y,
                    child: Text(y ?? 'All', style: TextStyle(color: colorScheme.onSurface, fontSize: 14)),
                  ))
              .toList(),
          onChanged: (v) {
            setState(() => _academicYear = v);
          },
        ),
      ),
    );
  }

  Widget _buildDateField(ColorScheme colorScheme) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: _attendanceDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2030),
        );
        if (picked != null && mounted) setState(() => _attendanceDate = picked);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              app_date_utils.DateUtils.formatAttendanceDate(_attendanceDate),
              style: TextStyle(color: colorScheme.onSurface, fontSize: 14, fontFamily: 'Questrial'),
            ),
            const SizedBox(width: 8),
            Icon(Icons.calendar_today, size: 20, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _buildTable(BuildContext context, ColorScheme colorScheme, List<Student> students) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth;
        return RepaintBoundary(
          child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: tableWidth,
              child: Table(
                columnWidths: {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(0.6),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(0.5),
                },
                border: TableBorder.all(color: colorScheme.outlineVariant),
                children: [
                  TableRow(
                    decoration: BoxDecoration(color: colorScheme.surfaceContainerHighest),
                    children: [
                      _tableHeader(context, 'Student Name'),
                      _tableHeader(context, 'Present'),
                      _tableHeader(context, 'Notes'),
                      _tableHeader(context, '%'),
                    ],
                  ),
                  ...students.asMap().entries.map((e) {
                    final index = e.key;
                    final student = e.value;
                    final edit = _edits[student.id] ?? _RowEdit(present: false);
                    final isIncomplete = edit.percent < 100;
                    Color rowColor = index.isEven
                        ? colorScheme.surface
                        : colorScheme.surfaceContainerLow.withValues(alpha: 0.5);
                    if (isIncomplete) {
                      rowColor = AppColors.withdrawnStatusBackground;
                    }
                    // Ensure controller exists
                    // #region agent log
                    _debugLog('attendance_screen.dart:_buildTable', 'Checking controller for student', {'studentId': student.id, 'hasController': _noteControllers.containsKey(student.id)}, 'B');
                    // #endregion
                    _noteControllers[student.id] ??= TextEditingController(text: edit.notes);
                    // #region agent log
                    _debugLog('attendance_screen.dart:_buildTable', 'Controller ensured', {'studentId': student.id, 'controllerIsNull': _noteControllers[student.id] == null}, 'B');
                    // #endregion
                    final controller = _noteControllers[student.id]!;
                    return TableRow(
                      decoration: BoxDecoration(color: rowColor),
                      children: [
                        _cell(context, colorScheme, Text('${student.surname} ${student.firstName}', style: TextStyle(color: colorScheme.onSurface, fontSize: 14, fontFamily: 'Questrial'))),
                        _checkboxCell(context, colorScheme, edit.present, (v) => _updateEdit(student.id, (e) => e.present = v)),
                        _cell(context, colorScheme, TextField(
                          onChanged: (v) => _updateEdit(student.id, (e) => e.notes = v),
                          controller: controller,
                          decoration: InputDecoration(
                            hintText: 'Add notes...',
                            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            isDense: true,
                          ),
                          style: TextStyle(color: colorScheme.onSurface, fontSize: 13),
                        )),
                        _cell(context, colorScheme, Text('${edit.percent}%', style: TextStyle(color: colorScheme.onSurface, fontSize: 14, fontFamily: 'Questrial'))),
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

  void _updateEdit(int studentId, void Function(_RowEdit) update) {
    final e = _edits[studentId];
    if (e != null) {
      update(e);
      setState(() {});
    }
  }

  Widget _tableHeader(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, ColorScheme colorScheme, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: child,
    );
  }

  Widget _checkboxCell(BuildContext context, ColorScheme colorScheme, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Center(
        child: Checkbox(
          value: value,
          onChanged: (v) => onChanged(v ?? false),
          activeColor: AppColors.primaryActionRed,
          checkColor: AppColors.charisWhite,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }

  Widget _buildSaveButton(ColorScheme colorScheme) {
    return ElevatedButton.icon(
      onPressed: _save,
      icon: const Icon(Icons.save, size: 20, color: AppColors.charisWhite),
      label: const Text('Save Changes', style: TextStyle(color: AppColors.charisWhite, fontFamily: 'Questrial', fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primaryActionRed,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _save() async {
    // #region agent log
    _debugLog('attendance_screen.dart:_save', 'Save method called', {'date': _attendanceDate.toString(), 'editsCount': _edits.length}, 'E');
    // #endregion
    final repo = ref.read(attendanceRepositoryProvider);
    final studentRepo = ref.read(studentRepositoryProvider);
    
    // Get current filtered students list directly from repository
    // #region agent log
    _debugLog('attendance_screen.dart:_save', 'Getting students stream', {}, 'C');
    // #endregion
    final allStudentsStream = studentRepo.watchStudents(statusFilter: 'Active');
    // #region agent log
    _debugLog('attendance_screen.dart:_save', 'Waiting for stream first value', {}, 'C');
    // #endregion
    final allStudents = await allStudentsStream.first;
    // #region agent log
    _debugLog('attendance_screen.dart:_save', 'Got students from stream', {'count': allStudents.length}, 'C');
    // #endregion
    
    final filtered = allStudents
        .where((s) => s.mode == _selectedMode)
        .where((s) => _academicYear == null || s.year == _academicYear)
        .toList();
    final students = sortStudentsAlphabetically(filtered);
    // #region agent log
    _debugLog('attendance_screen.dart:_save', 'Filtered students', {'filteredCount': students.length, 'selectedMode': _selectedMode, 'academicYear': _academicYear}, 'E');
    // #endregion
    
    // Ensure all students are included in the save, with their current checkbox state
    final entries = students.map((student) {
      // #region agent log
      _debugLog('attendance_screen.dart:_save', 'Processing student entry', {'studentId': student.id, 'hasEdit': _edits.containsKey(student.id)}, 'E');
      // #endregion
      final edit = _edits[student.id] ?? _RowEdit(present: false);
      return AttendanceEntry(
        studentId: student.id,
        present: edit.present, // Explicitly use the current checkbox state (false if unchecked)
        notes: edit.notes.isEmpty ? null : edit.notes,
      );
    }).toList();
    // #region agent log
    _debugLog('attendance_screen.dart:_save', 'Created entries', {'entriesCount': entries.length}, 'E');
    // #endregion
    
    try {
      // Get userId for change set logging
      final auth = ref.read(authStateProvider).valueOrNull;
      final userId = auth is Authenticated ? auth.user.id : null;
      
      // #region agent log
      _debugLog('attendance_screen.dart:_save', 'Calling upsertAttendanceForDate', {'entriesCount': entries.length}, 'A');
      // #endregion
      await repo.upsertAttendanceForDate(_attendanceDate, entries, userId: userId);
      // #region agent log
      _debugLog('attendance_screen.dart:_save', 'Upsert completed successfully', {}, 'A');
      // #endregion
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance saved.')));
      }
    } catch (e, stackTrace) {
      // #region agent log
      _debugLog('attendance_screen.dart:_save', 'Error in save', {'error': e.toString(), 'stackTrace': stackTrace.toString()}, 'A');
      // #endregion
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
