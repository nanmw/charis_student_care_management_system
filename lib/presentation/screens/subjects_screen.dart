import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/subject_providers.dart';
import 'package:charis_student_care/data/repositories/subject_repository.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/theme/app_table_style.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:charis_student_care/presentation/widgets/subject_form_dialog.dart';

/// Subjects management screen: list subjects by year with add/edit/delete.
class SubjectsScreen extends ConsumerStatefulWidget {
  const SubjectsScreen({super.key});

  @override
  ConsumerState<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends ConsumerState<SubjectsScreen> {
  int? _selectedClassId;
  SubjectDataSource? _dataSource;
  int _displayedCount = 20; // Initial batch size
  bool _isLoadingMore = false;

  void _loadMore(int total) {
    if (_isLoadingMore || _displayedCount >= total) return;
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
    final redColor = isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final classesAsync = ref.watch(allClassesFutureProvider);
    final classes = classesAsync.valueOrNull;
    final effectiveClassId = _selectedClassId ??
        (classes != null && classes.isNotEmpty ? classes.first.id : null);
    final subjectsAsync = ref.watch(subjectsForClassStreamProvider(effectiveClassId ?? 0));

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
                'Subjects Management',
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
                      onPressed: () => context.go('/reports?type=subjects'),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Export'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RoleGuard(
                    canShow: RolePermissions.canManageSubjects,
                    child: ElevatedButton.icon(
                  onPressed: () => _openAddSubject(context),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add Subject'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: redColor,
                    foregroundColor: AppColors.charisWhite,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
              _buildClassDropdown(classes),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: subjectsAsync.when(
              data: (subjects) {
                if (subjects.isEmpty) {
                  String selectedName = 'selected class';
                  if (effectiveClassId != null && classes != null) {
                    for (final c in classes) {
                      if (c.id == effectiveClassId) {
                        selectedName = c.name;
                        break;
                      }
                    }
                  }
                  return Center(
                    child: Text(
                      'No subjects found for $selectedName.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontFamily: 'Questrial',
                      ),
                    ),
                  );
                }
                // Reset displayed count if year changed
                final total = subjects.length;
                if (_displayedCount > total) {
                  _displayedCount = total;
                }
                final displayedSubjects = subjects.sublist(0, _displayedCount.clamp(0, total));
                final canManage = RolePermissions.canManageSubjects(
                  (ref.read(authStateProvider).valueOrNull as Authenticated?)?.role ??
                      UserRole.facilitator,
                );
                _dataSource ??= SubjectDataSource(
                  subjects: displayedSubjects,
                  totalCount: total,
                  colorScheme: colorScheme,
                  onEdit: (s) => _openEditSubject(context, s),
                  onDelete: (s) => _deleteSubject(context, s),
                  onMoveUp: (s) => _moveSubject(context, s, SubjectMoveDirection.up),
                  onMoveDown: (s) => _moveSubject(context, s, SubjectMoveDirection.down),
                  canManage: canManage,
                );
                _dataSource!.updateData(
                  displayedSubjects,
                  total,
                  colorScheme,
                  (
                    (s) => _openEditSubject(context, s),
                    (s) => _deleteSubject(context, s),
                    (s) => _moveSubject(context, s, SubjectMoveDirection.up),
                    (s) => _moveSubject(context, s, SubjectMoveDirection.down),
                    canManage,
                  ),
                );
                return NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollUpdateNotification) {
                      final metrics = notification.metrics;
                      if (metrics.pixels >= metrics.maxScrollExtent * 0.8 &&
                          _displayedCount < total &&
                          !_isLoadingMore) {
                        _loadMore(total);
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
                          width: 80,
                          label: AppTableStyle.sfHeaderCell(
                            context,
                            'S/N',
                            compactLineHeight: true,
                          ),
                        ),
                        GridColumn(
                          columnName: 'name',
                          width: double.nan,
                          label: AppTableStyle.sfHeaderCell(
                            context,
                            'Subject Name',
                            compactLineHeight: true,
                          ),
                        ),
                        GridColumn(
                          columnName: 'actions',
                          width: 260,
                          label: AppTableStyle.sfHeaderCell(
                            context,
                            'Actions',
                            compactLineHeight: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  'Error loading subjects: $err',
                  style: TextStyle(
                    color: colorScheme.error,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassDropdown(List<SchoolClass>? classes) {
    final colorScheme = Theme.of(context).colorScheme;
    final list = classes ?? [];
    final value = _selectedClassId ?? (list.isNotEmpty ? list.first.id : null);
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: DropdownButton<int>(
        value: value,
        isExpanded: true,
        underline: const SizedBox(),
        items: list.map((c) => DropdownMenuItem<int>(value: c.id, child: Text(c.name, style: const TextStyle(fontSize: 14, fontFamily: 'Questrial')))).toList(),
        onChanged: (v) {
          if (v != null) {
            setState(() {
              _selectedClassId = v;
              _displayedCount = 20;
            });
          }
        },
      ),
    );
  }

  void _openAddSubject(BuildContext context) {
    final list = ref.read(allClassesFutureProvider).valueOrNull;
    final classId = _selectedClassId ?? (list != null && list.isNotEmpty ? list.first.id : null);
    if (classId == null) return;
    SubjectFormDialog.showAdd(
      context: context,
      ref: ref,
      classId: classId,
      onSaved: () {},
    );
  }

  void _openEditSubject(BuildContext context, Subject subject) {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return;
    if (!RolePermissions.canManageSubjects(auth.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You do not have permission to edit subjects')),
      );
      return;
    }
    SubjectFormDialog.showEdit(
      context: context,
      ref: ref,
      subject: subject,
      onSaved: () {},
    );
  }

  Future<void> _moveSubject(
    BuildContext context,
    Subject subject,
    SubjectMoveDirection direction,
  ) async {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return;
    if (!RolePermissions.canManageSubjects(auth.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You do not have permission to reorder subjects')),
      );
      return;
    }
    try {
      await ref.read(subjectRepositoryProvider).moveSubject(
            subject.id,
            direction,
            userRole: auth.role,
            userId: auth.user.id,
            userDisplayName: auth.user.displayName,
            screen: 'Subjects',
          );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reordering subject: $e')),
        );
      }
    }
  }

  Future<void> _deleteSubject(BuildContext context, Subject subject) async {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return;
    if (!RolePermissions.canManageSubjects(auth.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You do not have permission to delete subjects')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Subject', style: TextStyle(fontFamily: 'Questrial')),
        content: Text(
          'Are you sure you want to delete "${subject.name}"?',
          style: const TextStyle(fontFamily: 'Questrial'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.charisRedPrimary,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await ref.read(subjectRepositoryProvider).deleteSubject(
              subject.id,
              userRole: auth.role,
              userId: auth.user.id,
              userDisplayName: auth.user.displayName,
              screen: 'Subjects',
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Subject deleted successfully')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting subject: $e')),
          );
        }
      }
    }
  }
}

class SubjectDataSource extends DataGridSource {
  SubjectDataSource({
    required List<Subject> subjects,
    required int totalCount,
    required ColorScheme colorScheme,
    required void Function(Subject) onEdit,
    required void Function(Subject) onDelete,
    required void Function(Subject) onMoveUp,
    required void Function(Subject) onMoveDown,
    required bool canManage,
  })  : _subjects = subjects,
        _totalCount = totalCount,
        _colorScheme = colorScheme,
        _onEdit = onEdit,
        _onDelete = onDelete,
        _onMoveUp = onMoveUp,
        _onMoveDown = onMoveDown,
        _canManage = canManage {
    _buildRows();
  }

  List<Subject> _subjects;
  int _totalCount;
  ColorScheme _colorScheme;
  void Function(Subject) _onEdit;
  void Function(Subject) _onDelete;
  void Function(Subject) _onMoveUp;
  void Function(Subject) _onMoveDown;
  bool _canManage;

  List<DataGridRow> _dataGridRows = [];

  void updateData(
    List<Subject> subjects,
    int totalCount,
    ColorScheme colorScheme,
    (
      void Function(Subject),
      void Function(Subject),
      void Function(Subject),
      void Function(Subject),
      bool
    ) callbacks,
  ) {
    _subjects = subjects;
    _totalCount = totalCount;
    _colorScheme = colorScheme;
    _onEdit = callbacks.$1;
    _onDelete = callbacks.$2;
    _onMoveUp = callbacks.$3;
    _onMoveDown = callbacks.$4;
    _canManage = callbacks.$5;
    _buildRows();
    notifyListeners();
  }

  void _buildRows() {
    _dataGridRows = _subjects
        .asMap()
        .entries
        .map((e) => DataGridRow(cells: [
              DataGridCell<int>(columnName: 'sn', value: e.key + 1),
              DataGridCell<String>(columnName: 'name', value: e.value.name),
              DataGridCell<(Subject, int)>(
                columnName: 'actions',
                value: (e.value, e.key),
              ),
            ],),)
        .toList();
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter? buildRow(DataGridRow row) {
    final cells = row.getCells();
    final actionCell =
        cells.firstWhere((c) => c.columnName == 'actions').value as (Subject, int);
    final subject = actionCell.$1;
    final index = actionCell.$2;
    final canMoveUp = index > 0;
    final canMoveDown = index < _totalCount - 1;
    return DataGridRowAdapter(
      color: _colorScheme.surface,
      cells: cells.map<Widget>((cell) {
        if (cell.columnName == 'actions') {
          return Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_canManage) ...[
                    IconButton(
                      tooltip: 'Move up',
                      onPressed: canMoveUp ? () => _onMoveUp(subject) : null,
                      icon: Icon(
                        Icons.arrow_upward,
                        size: 16,
                        color: canMoveUp
                            ? _colorScheme.onSurfaceVariant
                            : _colorScheme.outlineVariant,
                      ),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                    IconButton(
                      tooltip: 'Move down',
                      onPressed: canMoveDown ? () => _onMoveDown(subject) : null,
                      icon: Icon(
                        Icons.arrow_downward,
                        size: 16,
                        color: canMoveDown
                            ? _colorScheme.onSurfaceVariant
                            : _colorScheme.outlineVariant,
                      ),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      padding: EdgeInsets.zero,
                    ),
                    TextButton.icon(
                      onPressed: () => _onEdit(subject),
                      icon: Icon(Icons.edit_outlined, size: 14, color: _colorScheme.onSurfaceVariant),
                      label: Text(
                        'Edit',
                        style: TextStyle(
                          color: _colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.1,
                          fontFamily: 'Questrial',
                        ),
                      ),
                      style: AppTableStyle.dataGridTextButtonStyle(),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () => _onDelete(subject),
                      icon: Icon(Icons.delete_outline, size: 14, color: _colorScheme.error),
                      label: Text(
                        'Delete',
                        style: TextStyle(
                          color: _colorScheme.error,
                          fontSize: 13,
                          height: 1.1,
                          fontFamily: 'Questrial',
                        ),
                      ),
                      style: AppTableStyle.dataGridTextButtonStyle(),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Container(
          padding: AppTableStyle.cellPadding,
          alignment: Alignment.centerLeft,
          child: Text(
            cell.value.toString(),
            style: AppTableStyle.dataGridBodyTextStyle(_colorScheme),
          ),
        );
      }).toList(),
    );
  }
}
