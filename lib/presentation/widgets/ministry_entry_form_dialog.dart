import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/ministry_providers.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/widgets/searchable_dropdown.dart';

/// Dialog to add a new ministry entry (student, year, type, date, hours, supervisor, approved, notes).
class MinistryEntryFormDialog extends ConsumerStatefulWidget {
  const MinistryEntryFormDialog({super.key, this.entry});

  /// If provided, dialog is in edit mode.
  final MinistryEntry? entry;

  @override
  ConsumerState<MinistryEntryFormDialog> createState() =>
      _MinistryEntryFormDialogState();
}

class _MinistryEntryFormDialogState
    extends ConsumerState<MinistryEntryFormDialog> {
  int? _studentId;
  String? _year;
  int? _term;
  int? _classId;
  String? _studyMode;
  String? _ministryType;
  DateTime? _date;
  final _hoursController = TextEditingController();
  final _supervisorController = TextEditingController();
  final _notesController = TextEditingController();
  bool _approved = false;

  static const List<int> _termOptions = [1, 2, 3];

  static List<String> get _yearOptions {
    final now = DateTime.now();
    return List.generate(5, (i) => (now.year - 2 + i).toString());
  }

  @override
  void initState() {
    super.initState();
    if (widget.entry != null) {
      final e = widget.entry!;
      _studentId = e.studentId;
      _year = e.year;
      _term = e.term;
      _classId = e.classId;
      _studyMode = e.studyMode;
      _ministryType = e.ministryType;
      _date = e.date;
      _hoursController.text = e.hours.toString();
      _supervisorController.text = e.supervisor ?? '';
      _notesController.text = e.notes ?? '';
      _approved = e.approved;
    } else {
      _date = DateTime.now();
      _year = DateTime.now().year.toString();
    }
  }

  @override
  void dispose() {
    _hoursController.dispose();
    _supervisorController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_studentId == null ||
        _year == null ||
        _term == null ||
        _ministryType == null ||
        _date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select student, year, term, type and date.')),
      );
      return;
    }
    final hours = double.tryParse(_hoursController.text.trim());
    if (hours == null || hours < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid hours value.')),
      );
      return;
    }

    final repo = ref.read(ministryEntryRepositoryProvider);
    final supervisor = _supervisorController.text.trim().isEmpty
        ? null
        : _supervisorController.text.trim();
    final notes = _notesController.text.trim().isEmpty
        ? null
        : _notesController.text.trim();

    try {
      if (widget.entry != null) {
        await repo.update(
          widget.entry!.id,
          MinistryEntriesCompanion(
            studentId: Value(_studentId!),
            year: Value(_year!),
            term: Value(_term!),
            classId: Value(_classId),
            studyMode: Value(_studyMode),
            ministryType: Value(_ministryType!),
            date: Value(_date!),
            hours: Value(hours),
            supervisor: Value(supervisor),
            approved: Value(_approved),
            notes: Value(notes),
            updatedAt: Value(DateTime.now()),
          ),
        );
      } else {
        final now = DateTime.now();
        await repo.insert(
          MinistryEntriesCompanion(
            studentId: Value(_studentId!),
            year: Value(_year!),
            term: Value(_term!),
            classId: Value(_classId),
            studyMode: Value(_studyMode),
            ministryType: Value(_ministryType!),
            date: Value(_date!),
            hours: Value(hours),
            supervisor: Value(supervisor),
            approved: Value(_approved),
            notes: Value(notes),
            createdAt: Value(now),
            updatedAt: const Value.absent(),
          ),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
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

    return AlertDialog(
      backgroundColor: isDark ? null : AppColors.charisWhite,
      title: Text(
        widget.entry != null ? 'Edit Ministry Entry' : 'Add Ministry Entry',
        style: const TextStyle(fontFamily: 'Questrial'),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 480,
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: SingleChildScrollView(
          child: studentsAsync.when(
            data: (students) {
              final studentMap = {for (final s in students) s.id: s};
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SearchableDropdown<int>(
                    items: students.map((s) => s.id).toList(),
                    selectedValue: _studentId,
                    hint: 'Select student',
                    searchHint: 'Search students...',
                    itemBuilder: (context, id) {
                      final s = studentMap[id];
                      return Text(
                        s != null ? '${s.surname}, ${s.firstName}' : '$id',
                        style: TextStyle(
                          color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
                          fontSize: 14,
                          fontFamily: 'Questrial',
                        ),
                      );
                    },
                    displayTextBuilder: (id) {
                      final s = studentMap[id];
                      return s != null ? '${s.surname}, ${s.firstName}' : '$id';
                    },
                    searchFilter: (id, query) {
                      final s = studentMap[id];
                      if (s == null) return false;
                      final q = query.toLowerCase();
                      return s.surname.toLowerCase().contains(q) ||
                          s.firstName.toLowerCase().contains(q);
                    },
                    onChanged: (v) {
                      setState(() {
                        _studentId = v;
                        if (v != null) {
                          final s = studentMap[v];
                          if (s != null) {
                            _classId = s.classId;
                            _studyMode = s.mode ?? 'Full-time';
                          }
                        }
                      });
                    },
                  ),
                  if (_classId != null && _studyMode != null) ...[
                    const SizedBox(height: 8),
                    _ClassModeLabel(classId: _classId!, studyMode: _studyMode!),
                  ],
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    initialValue: _term,
                    decoration: InputDecoration(
                      labelText: 'Term',
                      border: const OutlineInputBorder(),
                      fillColor: isDark ? AppColors.surfaceDark : null,
                      labelStyle: TextStyle(
                        color: isDark ? AppColors.textSecondaryOnDark : null,
                      ),
                    ),
                    style: TextStyle(
                      color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
                      fontSize: 14,
                      fontFamily: 'Questrial',
                    ),
                    items: _termOptions
                        .map((t) => DropdownMenuItem(value: t, child: Text('Term $t')))
                        .toList(),
                    onChanged: (v) => setState(() => _term = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _year,
                    decoration: InputDecoration(
                      labelText: 'Year',
                      border: const OutlineInputBorder(),
                      fillColor: isDark ? AppColors.surfaceDark : null,
                      labelStyle: TextStyle(
                        color: isDark ? AppColors.textSecondaryOnDark : null,
                      ),
                    ),
                    style: TextStyle(
                      color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
                      fontSize: 14,
                      fontFamily: 'Questrial',
                    ),
                    items: _yearOptions
                        .map((y) => DropdownMenuItem(value: y, child: Text(y)))
                        .toList(),
                    onChanged: (v) => setState(() => _year = v),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _ministryType,
                    decoration: InputDecoration(
                      labelText: 'Ministry Type',
                      border: const OutlineInputBorder(),
                      fillColor: isDark ? AppColors.surfaceDark : null,
                      labelStyle: TextStyle(
                        color: isDark ? AppColors.textSecondaryOnDark : null,
                      ),
                    ),
                    style: TextStyle(
                      color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
                      fontSize: 14,
                      fontFamily: 'Questrial',
                    ),
                    items: AppConstants.ministryTypeOptions
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text(t),
                            ),)
                        .toList(),
                    onChanged: (v) => setState(() => _ministryType = v),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Date', style: TextStyle(fontFamily: 'Questrial')),
                    subtitle: Text(
                      _date != null
                          ? DateFormat('yyyy-MM-dd').format(_date!)
                          : 'Select date',
                      style: const TextStyle(fontFamily: 'Questrial'),
                    ),
                    trailing: const Icon(Icons.calendar_today),
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
                  const SizedBox(height: 8),
                  TextField(
                    controller: _hoursController,
                    decoration: const InputDecoration(
                      labelText: 'Hours',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: false,),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _supervisorController,
                    decoration: const InputDecoration(
                      labelText: 'Supervisor (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: _approved,
                    onChanged: (v) => setState(() => _approved = v ?? false),
                    title: const Text(
                      'Approved',
                      style: TextStyle(fontFamily: 'Questrial'),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                    maxLines: 2,
                  ),
                ],
              );
            },
            loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),),
            error: (e, _) => Text('Error loading students: $e'),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: redColor),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Displays class name and study mode (e.g. "Year 1 • Full-time").
class _ClassModeLabel extends ConsumerWidget {
  const _ClassModeLabel({required this.classId, required this.studyMode});

  final int classId;
  final String studyMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final classAsync = ref.watch(classByIdProvider(classId));
    return classAsync.when(
      data: (SchoolClass? c) => Text(
        '${c?.name ?? 'Class $classId'} • $studyMode',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontFamily: 'Questrial',
        ),
      ),
      loading: () => Text(
        '• $studyMode',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontFamily: 'Questrial',
        ),
      ),
      error: (_, __) => Text(
        '• $studyMode',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontFamily: 'Questrial',
        ),
      ),
    );
  }
}
