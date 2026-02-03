import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/domain/use_cases/sort_students_alphabetically.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:charis_student_care/presentation/widgets/student_form_dialog.dart';

/// Main content for Students List (shell provides header/sidebar/footer).
class StudentListScreen extends ConsumerStatefulWidget {
  const StudentListScreen({super.key});

  @override
  ConsumerState<StudentListScreen> createState() => _StudentListScreenState();
}

/// Year options for filter (Year 1–3 + All).
const List<String?> _yearFilterOptions = [null, 'Year 1', 'Year 2', 'Year 3'];

/// Mode options for filter (Full-time, Hybrid + All).
const List<String?> _modeFilterOptions = [null, 'Full-time', 'Hybrid'];

class _StudentListScreenState extends ConsumerState<StudentListScreen> {
  String? _statusFilter = 'Active';
  String? _yearFilter;
  String? _modeFilter;
  String _searchQuery = '';
  int _pageSize = 10;
  int _currentPage = 0;
  StudentDataSource? _dataSource;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final studentsAsync = ref.watch(studentsStreamProvider(_statusFilter));

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
              RoleGuard(
                canShow: RolePermissions.canManageStudents,
                child: ElevatedButton.icon(
                  onPressed: () => _openAddStudent(context),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add Student'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryActionRed,
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
              _buildSearchField(),
              const SizedBox(width: 12),
              _buildYearDropdown(),
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
                if (_yearFilter != null) {
                  filtered = filtered.where((s) => s.year == _yearFilter).toList();
                }
                if (_modeFilter != null) {
                  filtered = filtered.where((s) => s.mode == _modeFilter).toList();
                }
                final total = filtered.length;
                final start = _currentPage * _pageSize;
                final pageStudents = total == 0
                    ? <Student>[]
                    : filtered.sublist(start, (start + _pageSize).clamp(0, total));
                _dataSource ??= StudentDataSource(
                  students: pageStudents,
                  startIndex: start,
                  colorScheme: colorScheme,
                  onEdit: (s) => _openEditStudent(context, s, ref),
                  onWithdraw: (s) => _applyStatus(context, ref, s, 'Withdrawn'),
                  onTransfer: (s) => _applyStatus(context, ref, s, 'Transferred'),
                  canManage: RolePermissions.canManageStudents(
                    (ref.read(authStateProvider).valueOrNull as Authenticated?)?.role ?? UserRole.facilitator,
                  ),
                );
                _dataSource!.updateData(
                  pageStudents,
                  start,
                  colorScheme,
                  (
                    (s) => _openEditStudent(context, s, ref),
                    (s) => _applyStatus(context, ref, s, 'Withdrawn'),
                    (s) => _applyStatus(context, ref, s, 'Transferred'),
                    RolePermissions.canManageStudents(
                      (ref.read(authStateProvider).valueOrNull as Authenticated?)?.role ?? UserRole.facilitator,
                    ),
                  ),
                );
                if (pageStudents.isEmpty && filtered.isNotEmpty) {
                  _currentPage = ((filtered.length - 1) / _pageSize).floor();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: RepaintBoundary(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SfDataGrid(
                          source: _dataSource!,
                          columnWidthMode: ColumnWidthMode.fill,
                          gridLinesVisibility: GridLinesVisibility.both,
                          headerGridLinesVisibility: GridLinesVisibility.both,
                          headerRowHeight: 44,
                          rowHeight: 48,
                          columns: [
                            GridColumn(columnName: 'sn', label: _header(context, 'S/N'), width: 56),
                            GridColumn(columnName: 'surname', label: _header(context, 'Surname'), width: 120),
                            GridColumn(columnName: 'firstName', label: _header(context, 'First Names'), width: 120),
                            GridColumn(columnName: 'year', label: _header(context, 'Year'), width: 80),
                            GridColumn(columnName: 'mode', label: _header(context, 'Mode'), width: 90),
                            GridColumn(columnName: 'status', label: _header(context, 'Status'), width: 100),
                            GridColumn(columnName: 'contactInfo', label: _header(context, 'Phone'), width: 120),
                            GridColumn(columnName: 'email', label: _header(context, 'Email'), width: 140),
                            GridColumn(columnName: 'handbook', label: _header(context, 'Handbook'), width: 90),
                            GridColumn(columnName: 'mediaRelease', label: _header(context, 'Media Release'), width: 110),
                            GridColumn(columnName: 'accidentWaiver', label: _header(context, 'Accident Waiver'), width: 120),
                            GridColumn(columnName: 'actions', label: _header(context, 'Actions'), width: 300),
                          ],
                        ),
                      ),
                    ),
                  ),
                    _buildPagination(total),
                  ],
                );
              },
              loading: () => Center(child: CircularProgressIndicator(color: colorScheme.onSurface)),
              error: (err, _) => Center(child: Text('Error: $err', style: TextStyle(color: colorScheme.onSurface))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String text) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      alignment: Alignment.centerLeft,
      color: colorScheme.surfaceContainerHighest,
      child: Text(
        text,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          fontFamily: 'Questrial',
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 260,
      child: TextField(
        onChanged: (v) => setState(() {
          _searchQuery = v;
          _currentPage = 0;
        }),
        decoration: InputDecoration(
          hintText: 'Search students...',
          hintStyle: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
          prefixIcon: Icon(Icons.search, color: colorScheme.onSurfaceVariant, size: 22),
          filled: true,
          fillColor: colorScheme.surfaceContainerHighest,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
      ),
    );
  }

  Widget _buildFilterButton() {
    final colorScheme = Theme.of(context).colorScheme;
    return OutlinedButton.icon(
      onPressed: () => _showFilterMenu(),
      icon: const Icon(Icons.filter_list, size: 20),
      label: const Text('Filter'),
      style: OutlinedButton.styleFrom(
        foregroundColor: colorScheme.onSurfaceVariant,
        side: BorderSide(color: colorScheme.outline),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildYearDropdown() {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 100,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outline),
        ),
        child: DropdownButton<String?>(
        value: _yearFilter,
        hint: Text('Year', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
        isExpanded: true,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(8),
        items: _yearFilterOptions.map((v) => DropdownMenuItem<String?>(
          value: v,
          child: Text(v ?? 'All', style: TextStyle(color: colorScheme.onSurface, fontSize: 14)),
        )).toList(),
        onChanged: (v) => setState(() {
          _yearFilter = v;
          _currentPage = 0;
        }),
      ),
    ),
    );
  }

  Widget _buildModeDropdown() {
    final colorScheme = Theme.of(context).colorScheme;
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
        value: _modeFilter,
        hint: Text('Mode', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14)),
        isExpanded: true,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(8),
        items: _modeFilterOptions.map((v) => DropdownMenuItem<String?>(
          value: v,
          child: Text(v ?? 'All', style: TextStyle(color: colorScheme.onSurface, fontSize: 14)),
        )).toList(),
        onChanged: (v) => setState(() {
          _modeFilter = v;
          _currentPage = 0;
        }),
      ),
    ),
    );
  }

  void _showFilterMenu() {
    showMenu<String?>(
      context: context,
      position: const RelativeRect.fromLTRB(0, 80, 200, 0),
      items: [
        const PopupMenuItem(value: 'Active', child: Text('Active')),
        const PopupMenuItem(value: 'Withdrawn', child: Text('Withdrawn')),
        const PopupMenuItem(value: 'Transferred', child: Text('Transferred')),
        const PopupMenuItem(value: null, child: Text('All')),
      ],
    ).then((v) {
      setState(() {
        _statusFilter = v;
        _currentPage = 0;
      });
    });
  }

  Widget _buildPagination(int totalFiltered) {
    final colorScheme = Theme.of(context).colorScheme;
    final totalPages = totalFiltered == 0 ? 1 : ((totalFiltered - 1) / _pageSize).floor() + 1;
    final start = _currentPage * _pageSize;
    final end = (start + _pageSize).clamp(0, totalFiltered);
    final showing = totalFiltered == 0 ? 0 : end - start;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Showing $showing of $totalFiltered students',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14, fontFamily: 'Questrial'),
          ),
          Row(
            children: [
              IconButton(
                onPressed: _currentPage > 0
                    ? () => setState(() => _currentPage--)
                    : null,
                icon: Icon(Icons.chevron_left, color: colorScheme.onSurface),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primaryActionRed,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_currentPage + 1}',
                  style: const TextStyle(color: AppColors.charisWhite, fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              IconButton(
                onPressed: _currentPage < totalPages - 1
                    ? () => setState(() => _currentPage++)
                    : null,
                icon: Icon(Icons.chevron_right, color: colorScheme.onSurface),
              ),
            ],
          ),
        ],
      ),
    );
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
      (ref.read(authStateProvider).valueOrNull as Authenticated?)?.role ?? UserRole.facilitator,
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You do not have permission to edit students')),
      );
      return;
    }
    StudentFormDialog.showEdit(context: context, ref: ref, student: s, onSaved: () {});
  }

  Future<void> _applyStatus(BuildContext context, WidgetRef ref, Student s, String newStatus) async {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return;
    try {
      await ref.read(studentRepositoryProvider).updateStudent(
            s.id,
            status: newStatus,
            userRole: auth.role,
            userId: auth.user.id,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Status set to $newStatus')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }
}

class StudentDataSource extends DataGridSource {
  StudentDataSource({
    required List<Student> students,
    required int startIndex,
    required ColorScheme colorScheme,
    required void Function(Student) onEdit,
    required void Function(Student) onWithdraw,
    required void Function(Student) onTransfer,
    required bool canManage,
  })  : _students = students,
        _startIndex = startIndex,
        _colorScheme = colorScheme,
        _onEdit = onEdit,
        _onWithdraw = onWithdraw,
        _onTransfer = onTransfer,
        _canManage = canManage {
    _buildRows();
  }

  List<Student> _students;
  int _startIndex;
  ColorScheme _colorScheme;
  void Function(Student) _onEdit;
  void Function(Student) _onWithdraw;
  void Function(Student) _onTransfer;
  bool _canManage;

  List<DataGridRow> _dataGridRows = [];

  void updateData(
    List<Student> students,
    int startIndex,
    ColorScheme colorScheme,
    (void Function(Student), void Function(Student), void Function(Student), bool) callbacks,
  ) {
    _students = students;
    _startIndex = startIndex;
    _colorScheme = colorScheme;
    _onEdit = callbacks.$1;
    _onWithdraw = callbacks.$2;
    _onTransfer = callbacks.$3;
    _canManage = callbacks.$4;
    _buildRows();
    notifyListeners();
  }

  void _buildRows() {
    _dataGridRows = _students
        .asMap()
        .entries
        .map((e) => DataGridRow(cells: [
              DataGridCell<int>(columnName: 'sn', value: _startIndex + e.key + 1),
              DataGridCell<String>(columnName: 'surname', value: e.value.surname),
              DataGridCell<String>(columnName: 'firstName', value: e.value.firstName),
              DataGridCell<String>(columnName: 'year', value: e.value.year ?? ''),
              DataGridCell<String>(columnName: 'mode', value: e.value.mode ?? ''),
              DataGridCell<String>(columnName: 'status', value: e.value.status),
              DataGridCell<String>(columnName: 'contactInfo', value: e.value.contactInfo ?? ''),
              DataGridCell<String>(columnName: 'email', value: e.value.email ?? ''),
              DataGridCell<bool>(columnName: 'handbook', value: e.value.handbook),
              DataGridCell<bool>(columnName: 'mediaRelease', value: e.value.mediaRelease),
              DataGridCell<bool>(columnName: 'accidentWaiver', value: e.value.accidentWaiver),
              DataGridCell<Student>(columnName: 'actions', value: e.value),
            ]))
        .toList();
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter? buildRow(DataGridRow row) {
    final cells = row.getCells();
    final student = cells.firstWhere((c) => c.columnName == 'actions').value as Student;
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
                      onPressed: () => _onEdit(student),
                      icon: Icon(Icons.edit_outlined, size: 18, color: _colorScheme.onSurfaceVariant),
                      label: Text('Edit', style: TextStyle(color: _colorScheme.onSurfaceVariant, fontSize: 13)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Material(
                      color: AppColors.primaryActionRed,
                      borderRadius: BorderRadius.circular(6),
                      child: InkWell(
                        onTap: () => _onWithdraw(student),
                        borderRadius: BorderRadius.circular(6),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_off_outlined, size: 16, color: AppColors.charisWhite),
                              const SizedBox(width: 4),
                              Text('Withdraw', style: TextStyle(color: AppColors.charisWhite, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    OutlinedButton.icon(
                      onPressed: () => _onTransfer(student),
                      icon: const Icon(Icons.swap_horiz, size: 18),
                      label: const Text('Transfer', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _colorScheme.onSurfaceVariant,
                        side: BorderSide(color: _colorScheme.outline),
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
        if (cell.columnName == 'status' && (cell.value?.toString() ?? '') == 'Withdrawn') {
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.withdrawnStatusBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primaryActionRed),
                  ),
                  child: Text(
                    'Withdrawn',
                    style: TextStyle(
                      color: AppColors.primaryActionRed,
                      fontSize: 13,
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
        if (cell.columnName == 'handbook' || cell.columnName == 'mediaRelease' || cell.columnName == 'accidentWaiver') {
          final boolValue = cell.value as bool? ?? false;
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              boolValue ? Icons.check_circle : Icons.circle_outlined,
              color: boolValue ? AppColors.primaryActionRed : _colorScheme.onSurfaceVariant,
              size: 20,
            ),
          );
        }
        return Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            cell.value?.toString() ?? '',
            style: TextStyle(color: _colorScheme.onSurface, fontSize: 14, fontFamily: 'Questrial'),
            overflow: TextOverflow.ellipsis,
          ),
        );
      }).toList(),
    );
  }
}
