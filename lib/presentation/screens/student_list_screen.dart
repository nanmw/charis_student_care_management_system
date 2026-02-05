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
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
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
  int _displayedCount = 20; // Initial batch size
  bool _isLoadingMore = false;
  StudentDataSource? _dataSource;
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
    final redColor = isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
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
              Row(
                children: [
                  RoleGuard(
                    canShow: RolePermissions.canManageStudents,
                    child: ElevatedButton.icon(
                      onPressed: () => _openAddStudent(context),
                      icon: const Icon(Icons.add, size: 20),
                      label: const Text('Add Student'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: redColor,
                        foregroundColor: AppColors.charisWhite,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
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
                  onEdit: (s) => _openEditStudent(context, s, ref),
                  onWithdraw: (s) => _applyStatus(context, ref, s, 'Withdrawn'),
                  onTransfer: (s) => _toggleMode(context, ref, s),
                  onCorrespondence: (s) => _applyStatus(context, ref, s, 'Correspondence'),
                  canManage: RolePermissions.canManageStudents(
                    (ref.read(authStateProvider).valueOrNull as Authenticated?)?.role ?? UserRole.facilitator,
                  ),
                );
                _dataSource!.updateData(
                  displayedStudents,
                  colorScheme,
                  (
                    (s) => _openEditStudent(context, s, ref),
                    (s) => _applyStatus(context, ref, s, 'Withdrawn'),
                    (s) => _toggleMode(context, ref, s),
                    (s) => _applyStatus(context, ref, s, 'Correspondence'),
                    RolePermissions.canManageStudents(
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
                        _loadMore();
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
                          GridColumn(columnName: 'handbook', label: _header(context, 'Handbook'), width: 100),
                          GridColumn(columnName: 'mediaRelease', label: _header(context, 'Media Release'), width: 130),
                          GridColumn(columnName: 'accidentWaiver', label: _header(context, 'Accident Waiver'), width: 140),
                          GridColumn(columnName: 'actions', label: _header(context, 'Actions'), width: 140),
                        ],
                      ),
                    ),
                  ),
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
      constraints: const BoxConstraints(minHeight: 44), // Match headerRowHeight
      child: Text(
        text,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
          fontSize: 14,
          fontFamily: 'Questrial',
        ),
        softWrap: false,
        overflow: TextOverflow.ellipsis,
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
          _displayedCount = 20; // Reset to initial batch
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
          _displayedCount = 20; // Reset to initial batch
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
          _displayedCount = 20; // Reset to initial batch
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
        const PopupMenuItem(value: 'Correspondence', child: Text('Correspondence')),
        const PopupMenuItem(value: null, child: Text('All')),
      ],
    ).then((v) {
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

  Future<void> _toggleMode(BuildContext context, WidgetRef ref, Student student) async {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return;

    // Determine new mode based on current mode
    String newMode;
    final currentMode = student.mode;
    if (currentMode == 'Full-time') {
      newMode = 'Hybrid';
    } else if (currentMode == 'Hybrid') {
      newMode = 'Full-time';
    } else {
      // Default to 'Full-time' if mode is null or empty
      newMode = 'Full-time';
    }

    try {
      await ref.read(studentRepositoryProvider).updateStudent(
        student.id,
        mode: newMode,
        userRole: auth.role,
        userId: auth.user.id,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mode changed to $newMode')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _handleBulkTickHandbook(BuildContext context, WidgetRef ref) async {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor = isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to perform this action')),
      );
      return;
    }

    if (!RolePermissions.canManageStudents(auth.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You do not have permission to perform this action')),
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
    if (_yearFilter != null) {
      filtered = filtered.where((s) => s.year == _yearFilter).toList();
    }
    if (_modeFilter != null) {
      filtered = filtered.where((s) => s.mode == _modeFilter).toList();
    }

    // Filter to only students with handbook=false
    final studentsToUpdate = filtered.where((s) => !s.handbook).toList();

    if (studentsToUpdate.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All filtered students already have handbook ticked')),
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
          style: TextStyle(fontFamily: 'Questrial', fontWeight: FontWeight.w600),
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
      final count = await ref.read(studentRepositoryProvider).bulkUpdateHandbook(
            studentIds: studentIds,
            userRole: auth.role,
            userId: auth.user.id,
          );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Handbook ticked for $count student${count == 1 ? '' : 's'}'),
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
    required void Function(Student) onEdit,
    required void Function(Student) onWithdraw,
    required void Function(Student) onTransfer,
    required void Function(Student) onCorrespondence,
    required bool canManage,
  })  : _students = students,
        _colorScheme = colorScheme,
        _redColor = redColor,
        _onEdit = onEdit,
        _onWithdraw = onWithdraw,
        _onTransfer = onTransfer,
        _onCorrespondence = onCorrespondence,
        _canManage = canManage {
    _buildRows();
  }

  List<Student> _students;
  ColorScheme _colorScheme;
  Color _redColor;
  void Function(Student) _onEdit;
  void Function(Student) _onWithdraw;
  void Function(Student) _onTransfer;
  void Function(Student) _onCorrespondence;
  bool _canManage;

  List<DataGridRow> _dataGridRows = [];

  void updateData(
    List<Student> students,
    ColorScheme colorScheme,
    (void Function(Student), void Function(Student), void Function(Student), void Function(Student), bool) callbacks,
  ) {
    _students = students;
    _colorScheme = colorScheme;
    _onEdit = callbacks.$1;
    _onWithdraw = callbacks.$2;
    _onTransfer = callbacks.$3;
    _onCorrespondence = callbacks.$4;
    _canManage = callbacks.$5;
    _buildRows();
    notifyListeners();
  }

  void _buildRows() {
    _dataGridRows = _students
        .asMap()
        .entries
        .map((e) => DataGridRow(cells: [
              DataGridCell<int>(columnName: 'sn', value: e.key + 1),
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
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_canManage) ...[
                  Tooltip(
                    message: 'Edit',
                    child: IconButton(
                      onPressed: () => _onEdit(student),
                      icon: Icon(Icons.edit_outlined, size: 20),
                      color: _colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.all(8),
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: 20, color: _colorScheme.onSurfaceVariant),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
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
                            Icon(Icons.person_off_outlined, size: 18, color: _colorScheme.error),
                            const SizedBox(width: 8),
                            Text('Withdraw', style: TextStyle(color: _colorScheme.error)),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'transfer',
                        child: Row(
                          children: [
                            Icon(Icons.swap_horiz, size: 18, color: _colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Text('Transfer'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'correspondence',
                        child: Row(
                          children: [
                            Icon(Icons.email_outlined, size: 18, color: _colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Text('Correspondence'),
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
                    border: Border.all(color: _redColor),
                  ),
                  child: Text(
                    'Withdrawn',
                    style: TextStyle(
                      color: _redColor,
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
        if (cell.columnName == 'status' && (cell.value?.toString() ?? '') == 'Correspondence') {
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 92),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.correspondenceStatusBackground,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.correspondenceStatusGreen),
                ),
                child: Text(
                  'Correspondence',
                  style: TextStyle(
                    color: AppColors.correspondenceStatusGreen,
                    fontSize: 12,
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
        if (cell.columnName == 'handbook' || cell.columnName == 'mediaRelease' || cell.columnName == 'accidentWaiver') {
          final boolValue = cell.value as bool? ?? false;
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              boolValue ? Icons.check_circle : Icons.circle_outlined,
              color: boolValue ? _redColor : _colorScheme.onSurfaceVariant,
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
