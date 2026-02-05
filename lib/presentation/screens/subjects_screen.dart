import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/subject_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:charis_student_care/presentation/widgets/subject_form_dialog.dart';

/// Subjects management screen: list subjects by year with add/edit/delete.
class SubjectsScreen extends ConsumerStatefulWidget {
  const SubjectsScreen({super.key});

  @override
  ConsumerState<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends ConsumerState<SubjectsScreen> {
  String _selectedYear = 'Year 1';
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
    final subjectsAsync = ref.watch(subjectsForYearStreamProvider(_selectedYear));

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
          const SizedBox(height: 20),
          Row(
            children: [
              _buildYearDropdown(),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: subjectsAsync.when(
              data: (subjects) {
                if (subjects.isEmpty) {
                  return Center(
                    child: Text(
                      'No subjects found for $_selectedYear.',
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
                _dataSource ??= SubjectDataSource(
                  subjects: displayedSubjects,
                  colorScheme: colorScheme,
                  onEdit: (s) => _openEditSubject(context, s),
                  onDelete: (s) => _deleteSubject(context, s),
                  canManage: RolePermissions.canManageSubjects(
                    (ref.read(authStateProvider).valueOrNull as Authenticated?)?.role ?? UserRole.facilitator,
                  ),
                );
                _dataSource!.updateData(
                  displayedSubjects,
                  colorScheme,
                  (
                    (s) => _openEditSubject(context, s),
                    (s) => _deleteSubject(context, s),
                    RolePermissions.canManageSubjects(
                      (ref.read(authStateProvider).valueOrNull as Authenticated?)?.role ?? UserRole.facilitator,
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
                        _loadMore(total);
                      }
                    }
                    return false;
                  },
                  child: RepaintBoundary(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SfDataGrid(
                        source: _dataSource!,
                        columnWidthMode: ColumnWidthMode.fill,
                        gridLinesVisibility: GridLinesVisibility.horizontal,
                        headerGridLinesVisibility: GridLinesVisibility.both,
                        columns: [
                        GridColumn(
                          columnName: 'sn',
                          width: 80,
                          label: Container(
                            padding: const EdgeInsets.all(8),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'S/N',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                fontFamily: 'Questrial',
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        GridColumn(
                          columnName: 'name',
                          width: double.nan,
                          label: Container(
                            padding: const EdgeInsets.all(8),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Subject Name',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                fontFamily: 'Questrial',
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                        GridColumn(
                          columnName: 'actions',
                          width: 150,
                          label: Container(
                            padding: const EdgeInsets.all(8),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Actions',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                fontFamily: 'Questrial',
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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

  Widget _buildYearDropdown() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.charisMidGray),
      ),
      child: DropdownButton<String>(
        value: _selectedYear,
        isExpanded: true,
        underline: const SizedBox(),
        items: SubjectFormDialog.yearOptions.map((year) {
          return DropdownMenuItem(
            value: year,
            child: Text(
              year,
              style: const TextStyle(
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _selectedYear = value;
              _displayedCount = 20; // Reset to initial batch
            });
          }
        },
      ),
    );
  }

  void _openAddSubject(BuildContext context) {
    SubjectFormDialog.showAdd(
      context: context,
      ref: ref,
      year: _selectedYear,
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
    required ColorScheme colorScheme,
    required void Function(Subject) onEdit,
    required void Function(Subject) onDelete,
    required bool canManage,
  })  : _subjects = subjects,
        _colorScheme = colorScheme,
        _onEdit = onEdit,
        _onDelete = onDelete,
        _canManage = canManage {
    _buildRows();
  }

  List<Subject> _subjects;
  ColorScheme _colorScheme;
  void Function(Subject) _onEdit;
  void Function(Subject) _onDelete;
  bool _canManage;

  List<DataGridRow> _dataGridRows = [];

  void updateData(
    List<Subject> subjects,
    ColorScheme colorScheme,
    (void Function(Subject), void Function(Subject), bool) callbacks,
  ) {
    _subjects = subjects;
    _colorScheme = colorScheme;
    _onEdit = callbacks.$1;
    _onDelete = callbacks.$2;
    _canManage = callbacks.$3;
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
              DataGridCell<Subject>(columnName: 'actions', value: e.value),
            ]))
        .toList();
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter? buildRow(DataGridRow row) {
    final cells = row.getCells();
    final subject = cells.firstWhere((c) => c.columnName == 'actions').value as Subject;
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
                    TextButton.icon(
                      onPressed: () => _onEdit(subject),
                      icon: Icon(Icons.edit_outlined, size: 18, color: _colorScheme.onSurfaceVariant),
                      label: Text('Edit', style: TextStyle(color: _colorScheme.onSurfaceVariant, fontSize: 13)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () => _onDelete(subject),
                      icon: Icon(Icons.delete_outline, size: 18, color: _colorScheme.error),
                      label: Text('Delete', style: TextStyle(color: _colorScheme.error, fontSize: 13)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          alignment: Alignment.centerLeft,
          child: Text(
            cell.value.toString(),
            style: TextStyle(
              color: _colorScheme.onSurface,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
          ),
        );
      }).toList(),
    );
  }
}
