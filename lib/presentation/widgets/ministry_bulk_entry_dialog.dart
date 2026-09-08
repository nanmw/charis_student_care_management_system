import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/domain/attendance/attendance_thresholds.dart';
import 'package:charis_student_care/domain/use_cases/sort_students_alphabetically.dart';
import 'package:charis_student_care/presentation/providers/academic_session_providers.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/presentation/providers/ministry_providers.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';

/// Dialog to log one ministry activity for many students in a class/mode.
class MinistryBulkEntryDialog extends ConsumerStatefulWidget {
  const MinistryBulkEntryDialog({super.key});

  @override
  ConsumerState<MinistryBulkEntryDialog> createState() =>
      _MinistryBulkEntryDialogState();
}

class _MinistryBulkEntryDialogState
    extends ConsumerState<MinistryBulkEntryDialog> {
  int? _classId;
  String? _studyMode;
  String? _year;
  int? _term;
  String? _ministryType;
  DateTime? _date;
  bool _approved = false;
  bool _saving = false;
  bool _didPrefillCohort = false;

  final _defaultHoursController = TextEditingController();
  final _supervisorController = TextEditingController();
  final _notesController = TextEditingController();
  final Map<int, TextEditingController> _hoursControllers = {};
  final Set<int> _selectedStudentIds = {};
  String _cohortKey = '';

  static const List<int> _termOptions = [1, 2, 3];

  static List<String> get _yearOptions {
    final now = DateTime.now();
    return List.generate(5, (i) => (now.year - 2 + i).toString());
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = now;
    _year = now.year.toString();
    _term = termNumberForMonth(now.month);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tryPrefillCohort();
    });
  }

  void _tryPrefillCohort() {
    if (_didPrefillCohort) return;
    final visibleClasses =
        ref.read(classesVisibleToCurrentUserProvider).valueOrNull;
    if (visibleClasses == null || visibleClasses.isEmpty) return;
    final modeOptions = ref.read(modeOptionsForCurrentUserProvider);
    final summaryClassId = ref.read(ministrySummaryClassIdProvider);
    final summaryStudyMode = ref.read(ministrySummaryStudyModeProvider);
    final classIds = visibleClasses.map((c) => c.id).toSet();
    setState(() {
      _didPrefillCohort = true;
      _classId = classIds.contains(summaryClassId)
          ? summaryClassId
          : visibleClasses.first.id;
      _studyMode = modeOptions.contains(summaryStudyMode)
          ? summaryStudyMode
          : (modeOptions.isNotEmpty ? modeOptions.first : 'Full-time');
    });
  }

  @override
  void dispose() {
    _defaultHoursController.dispose();
    _supervisorController.dispose();
    _notesController.dispose();
    for (final c in _hoursControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  InputDecoration _decoration(String label, bool isDark) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      fillColor: isDark ? AppColors.surfaceDark : null,
      labelStyle: TextStyle(
        color: isDark ? AppColors.textSecondaryOnDark : null,
      ),
      isDense: true,
    );
  }

  TextStyle _fieldStyle(bool isDark) {
    return TextStyle(
      color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
      fontSize: 14,
      fontFamily: 'Questrial',
    );
  }

  List<Student> _filteredStudents(List<Student> all) {
    if (_classId == null || _studyMode == null) return [];
    final filtered = all.where((s) {
      return s.classId == _classId && (s.mode ?? 'Full-time') == _studyMode;
    }).toList();
    return sortStudentsAlphabetically(filtered);
  }

  void _syncCohort(List<Student> students) {
    for (final s in students) {
      _hoursControllers.putIfAbsent(s.id, TextEditingController.new);
    }
    final key = '$_classId|$_studyMode|${students.map((s) => s.id).join(',')}';
    if (key == _cohortKey) return;
    _cohortKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _selectedStudentIds
          ..clear()
          ..addAll(students.map((s) => s.id));
        _pruneHoursControllers(students);
        _applyDefaultHoursToSelected();
      });
    });
  }

  void _pruneHoursControllers(List<Student> students) {
    final keep = students.map((s) => s.id).toSet();
    final toRemove =
        _hoursControllers.keys.where((id) => !keep.contains(id)).toList();
    for (final id in toRemove) {
      _hoursControllers.remove(id)?.dispose();
    }
    for (final s in students) {
      _hoursControllers.putIfAbsent(s.id, TextEditingController.new);
    }
  }

  void _applyDefaultHoursToSelected() {
    final hours = _defaultHoursController.text.trim();
    for (final id in _selectedStudentIds) {
      _hoursControllers.putIfAbsent(id, TextEditingController.new).text = hours;
    }
  }

  double? _hoursForStudent(int studentId) {
    final raw = _hoursControllers[studentId]?.text.trim() ?? '';
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<void> _save(List<Student> students) async {
    if (_saving) return;
    if (_classId == null ||
        _studyMode == null ||
        _year == null ||
        _term == null ||
        _ministryType == null ||
        _date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select class, mode, year, term, type and date.',
          ),
        ),
      );
      return;
    }

    final toInsert = <({Student student, double hours})>[];
    for (final s in students) {
      if (!_selectedStudentIds.contains(s.id)) continue;
      final hours = _hoursForStudent(s.id);
      if (hours == null || hours <= 0) continue;
      toInsert.add((student: s, hours: hours));
    }

    if (toInsert.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select at least one student with hours greater than 0.',
          ),
        ),
      );
      return;
    }

    final repo = ref.read(ministryEntryRepositoryProvider);
    final duplicateIds = await repo.findStudentsWithEntryOnDate(
      studentIds: toInsert.map((e) => e.student.id).toList(),
      date: _date!,
      ministryType: _ministryType!,
    );
    if (duplicateIds.isNotEmpty && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(
            'Possible duplicates',
            style: TextStyle(fontFamily: 'Questrial'),
          ),
          content: Text(
            '${duplicateIds.length} selected student(s) already have this '
            'type on this date. Continue?',
            style: const TextStyle(fontFamily: 'Questrial'),
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

    final auth = ref.read(authStateProvider).valueOrNull;
    final userId = auth is Authenticated ? auth.user.id : null;
    final deviceId = await ref.read(deviceIdProvider.future);
    final userDisplayName =
        auth is Authenticated ? auth.user.displayName : null;
    final supervisor = _supervisorController.text.trim().isEmpty
        ? null
        : _supervisorController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    int? academicSessionId;
    final sessionCode =
        ref.read(currentAcademicSessionProvider).valueOrNull?.trim();
    if (sessionCode != null && sessionCode.isNotEmpty) {
      academicSessionId = await ref
          .read(academicSessionRepositoryProvider)
          .getSessionIdByCode(sessionCode);
    }

    final now = DateTime.now();
    final companions = toInsert.map((row) {
      return MinistryEntriesCompanion(
        studentId: Value(row.student.id),
        year: Value(_year!),
        term: Value(_term!),
        classId: Value(row.student.classId),
        studyMode: Value(row.student.mode ?? _studyMode),
        ministryType: Value(_ministryType!),
        date: Value(_date!),
        hours: Value(row.hours),
        supervisor: Value(supervisor),
        approved: Value(_approved),
        notes: Value(notes),
        createdAt: Value(now),
        updatedAt: const Value.absent(),
        academicSessionId: academicSessionId != null
            ? Value(academicSessionId)
            : const Value.absent(),
      );
    }).toList();

    setState(() => _saving = true);
    try {
      final count = await repo.insertAll(
        companions,
        userRole: auth is Authenticated ? auth.role : UserRole.facilitator,
        userId: userId,
        deviceId: deviceId,
        userDisplayName: userDisplayName,
        screen: 'Ministry Hours',
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Saved $count ministry ${count == 1 ? 'entry' : 'entries'}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final studentsAsync = ref.watch(studentsStreamProvider('Active'));
    final classesAsync = ref.watch(classesVisibleToCurrentUserProvider);
    final modeOptions = ref.watch(modeOptionsForCurrentUserProvider);
    final visibleClasses = classesAsync.valueOrNull ?? [];
    if (!_didPrefillCohort && visibleClasses.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tryPrefillCohort();
      });
    }

    return AlertDialog(
      backgroundColor: isDark ? null : AppColors.charisWhite,
      title: const Text(
        'Bulk Add Ministry Hours',
        style: TextStyle(fontFamily: 'Questrial'),
      ),
      content: SizedBox(
        width: 780,
        height: MediaQuery.of(context).size.height * 0.78,
        child: studentsAsync.when(
          data: (allStudents) {
            final students = _filteredStudents(allStudents);
            _syncCohort(students);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSharedFields(
                  isDark: isDark,
                  visibleClasses: visibleClasses,
                  modeOptions: modeOptions,
                ),
                const SizedBox(height: 12),
                _buildStudentToolbar(students),
                const SizedBox(height: 8),
                Expanded(
                  child: students.isEmpty
                      ? Center(
                          child: Text(
                            'No active students in this class and mode.',
                            style: TextStyle(
                              fontFamily: 'Questrial',
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        )
                      : _buildStudentList(students, isDark),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error loading students: $e'),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  final all = studentsAsync.valueOrNull ?? [];
                  await _save(_filteredStudents(all));
                },
          style: FilledButton.styleFrom(backgroundColor: redColor),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _buildSharedFields({
    required bool isDark,
    required List<SchoolClass> visibleClasses,
    required List<String> modeOptions,
  }) {
    final classValue =
        _classId != null && visibleClasses.any((c) => c.id == _classId)
            ? _classId
            : null;
    final modeValue = _studyMode != null && modeOptions.contains(_studyMode)
        ? _studyMode
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('bulk_class_$classValue'),
                initialValue: classValue,
                decoration: _decoration('Class', isDark),
                style: _fieldStyle(isDark),
                items: visibleClasses
                    .map(
                      (c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _classId = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('bulk_mode_$modeValue'),
                initialValue: modeValue,
                decoration: _decoration('Study Mode', isDark),
                style: _fieldStyle(isDark),
                items: modeOptions
                    .map(
                      (m) => DropdownMenuItem(value: m, child: Text(m)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _studyMode = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('bulk_term_$_term'),
                initialValue: _term,
                decoration: _decoration('Term', isDark),
                style: _fieldStyle(isDark),
                items: _termOptions
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text('Term $t'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _term = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                key: ValueKey('bulk_year_$_year'),
                initialValue: _year,
                decoration: _decoration('Year', isDark),
                style: _fieldStyle(isDark),
                items: _yearOptions
                    .map(
                      (y) => DropdownMenuItem(value: y, child: Text(y)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _year = v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                key: ValueKey('bulk_type_$_ministryType'),
                initialValue: _ministryType,
                decoration: _decoration('Ministry Type', isDark),
                style: _fieldStyle(isDark),
                items: AppConstants.ministryTypeOptions
                    .map(
                      (t) => DropdownMenuItem(value: t, child: Text(t)),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _ministryType = v),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Date',
                  style: TextStyle(fontFamily: 'Questrial', fontSize: 13),
                ),
                subtitle: Text(
                  _date != null
                      ? DateFormat('yyyy-MM-dd').format(_date!)
                      : 'Select date',
                  style: const TextStyle(fontFamily: 'Questrial'),
                ),
                trailing: const Icon(Icons.calendar_today, size: 20),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null && mounted) {
                    setState(() => _date = picked);
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _defaultHoursController,
                decoration: _decoration('Default hours', isDark),
                style: _fieldStyle(isDark),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: false,
                ),
                onSubmitted: (_) {
                  setState(_applyDefaultHoursToSelected);
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () {
                setState(_applyDefaultHoursToSelected);
              },
              child: const Text('Apply to selected'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _supervisorController,
                decoration: _decoration('Supervisor (optional)', isDark),
                style: _fieldStyle(isDark),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _notesController,
                decoration: _decoration('Notes (optional)', isDark),
                style: _fieldStyle(isDark),
              ),
            ),
            const SizedBox(width: 8),
            Checkbox(
              value: _approved,
              onChanged: (v) => setState(() => _approved = v ?? false),
            ),
            const Text(
              'Approved',
              style: TextStyle(fontFamily: 'Questrial'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStudentToolbar(List<Student> students) {
    final selectedCount = _selectedStudentIds.length;
    return Row(
      children: [
        Text(
          'Students ($selectedCount of ${students.length} selected)',
          style: const TextStyle(
            fontFamily: 'Questrial',
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        TextButton(
          onPressed: () {
            setState(() {
              _selectedStudentIds
                ..clear()
                ..addAll(students.map((s) => s.id));
              _applyDefaultHoursToSelected();
            });
          },
          child: const Text('Select all'),
        ),
        TextButton(
          onPressed: () {
            setState(() => _selectedStudentIds.clear());
          },
          child: const Text('Select none'),
        ),
      ],
    );
  }

  Widget _buildStudentList(List<Student> students, bool isDark) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.separated(
        itemCount: students.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final s = students[index];
          final selected = _selectedStudentIds.contains(s.id);
          final hoursController =
              _hoursControllers.putIfAbsent(s.id, TextEditingController.new);
          return ListTile(
            dense: true,
            leading: Checkbox(
              value: selected,
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedStudentIds.add(s.id);
                  } else {
                    _selectedStudentIds.remove(s.id);
                  }
                });
              },
            ),
            title: Text(
              '${s.surname}, ${s.firstName}',
              style: const TextStyle(fontFamily: 'Questrial', fontSize: 14),
            ),
            trailing: SizedBox(
              width: 96,
              child: TextField(
                controller: hoursController,
                enabled: selected,
                decoration: _decoration('Hours', isDark),
                style: _fieldStyle(isDark),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: false,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
