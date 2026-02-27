import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:go_router/go_router.dart';
import 'package:charis_student_care/core/utils/date_utils.dart' as app_date_utils;
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/ministry_entry_repository.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/ministry_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/widgets/ministry_entry_form_dialog.dart';

/// Builds summary tab options from classes (classId + studyMode + label).
/// Uses each class's actual year (sortOrder) for the ordinal so facilitators
/// see e.g. "3rd Year Full-time" when assigned to Year 3, not "1st Year".
List<({int classId, String studyMode, String label})> _buildSummaryTabOptions(
  List<SchoolClass> classes,
) {
  const modes = ['Full-time', 'Hybrid'];
  const ordinals = ['1st', '2nd', '3rd'];
  final options = <({int classId, String studyMode, String label})>[];
  for (final c in classes) {
    final yearLevel = c.sortOrder >= 1 ? c.sortOrder : 1;
    final ord = yearLevel <= ordinals.length
        ? ordinals[yearLevel - 1]
        : '${yearLevel}th';
    for (final mode in modes) {
      options.add((
        classId: c.id,
        studyMode: mode,
        label: '$ord Year $mode',
      ),);
    }
  }
  return options;
}

/// Ministry Hours Dashboard: summary view (by year/mode) and entries table.
class MinistryHoursScreen extends ConsumerStatefulWidget {
  const MinistryHoursScreen({super.key});

  @override
  ConsumerState<MinistryHoursScreen> createState() =>
      _MinistryHoursScreenState();
}

class _MinistryHoursScreenState extends ConsumerState<MinistryHoursScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String? _selectedYear;
  String? _selectedType;
  DateTime? _dateFrom;
  DateTime? _dateTo;
  MinistryEntryDataSource? _dataSource;
  MinistryHoursSummaryDataSource? _summaryDataSource;
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialLoadDone && mounted) {
        _initialLoadDone = true;
        ref.read(ministryEntriesProvider.notifier).loadInitial();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  MinistryEntryFilters get _filters => MinistryEntryFilters(
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
        year: _selectedYear,
        ministryType: _selectedType,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );

  void _applyFilters() {
    ref.read(ministryEntriesProvider.notifier).setFiltersAndReload(_filters);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateFrom != null && _dateTo != null
          ? DateTimeRange(start: _dateFrom!, end: _dateTo!)
          : null,
    );
    if (picked != null && mounted) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
      _applyFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final summaryAsync = ref.watch(ministrySummaryStatsProvider);
    final entriesState = ref.watch(ministryEntriesProvider);
    final selectedClassId = ref.watch(ministrySummaryClassIdProvider);
    final selectedStudyMode = ref.watch(ministrySummaryStudyModeProvider);
    final summaryKey = (selectedClassId, selectedStudyMode);
    final summaryListAsync = ref.watch(ministryHoursSummaryProvider(summaryKey));
    final classesAsync = ref.watch(classesVisibleToCurrentUserProvider);
    final auth = ref.watch(authStateProvider).valueOrNull;
    final visibleClasses = classesAsync.valueOrNull ?? [];
    if (visibleClasses.isNotEmpty &&
        auth is Authenticated &&
        !visibleClasses.any((c) => c.id == selectedClassId)) {
      final year1 = visibleClasses.where((c) => c.name == 'Year 1');
      final defaultClassId = auth.role == UserRole.facilitator
          ? visibleClasses.first.id
          : (year1.isEmpty ? visibleClasses.first.id : year1.first.id);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(ministrySummaryClassIdProvider.notifier).state = defaultClassId;
        ref.read(ministrySummaryStudyModeProvider.notifier).state = 'Full-time';
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
                  'Ministry Hours Dashboard',
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
                  onPressed: () => context.go('/reports?type=ministry-hours'),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Export'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildStatCards(context, colorScheme, redColor, summaryAsync),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            labelColor: redColor,
            unselectedLabelColor: colorScheme.onSurfaceVariant,
            tabs: const [
              Tab(text: 'Summary'),
              Tab(text: 'Ministry Entries'),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                classesAsync.when(
                  data: (classes) => _buildSummaryTab(
                    context,
                    colorScheme,
                    redColor,
                    classes,
                    selectedClassId,
                    selectedStudyMode,
                    summaryListAsync,
                  ),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Error: $e')),
                ),
                _buildEntriesTab(
                  context,
                  colorScheme,
                  redColor,
                  entriesState,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTab(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    List<SchoolClass> classes,
    int selectedClassId,
    String studyMode,
    AsyncValue<List<MinistryHoursSummaryRow>> summaryListAsync,
  ) {
    final summaryTabOptions = _buildSummaryTabOptions(classes);
    final idx = classes.indexWhere((c) => c.id == selectedClassId);
    final selectedClass = idx >= 0 ? classes[idx] : null;
    final yearLevel = selectedClass != null ? selectedClass.sortOrder : 1;
    final requirementText =
        AppConstants.ministryHoursRequirementText(studyMode, yearLevel);
    final reqMap = studyMode == 'Full-time'
        ? AppConstants.ministryHoursRequirements['FullTime']
        : AppConstants.ministryHoursRequirements['Hybrid'];
    final requiredHours = (reqMap != null ? reqMap[yearLevel] : null) ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: summaryTabOptions.map((opt) {
            final selected =
                opt.classId == selectedClassId && opt.studyMode == studyMode;
            return FilterChip(
              label: Text(opt.label),
              selected: selected,
              onSelected: (_) {
                ref.read(ministrySummaryClassIdProvider.notifier).state =
                    opt.classId;
                ref.read(ministrySummaryStudyModeProvider.notifier).state =
                    opt.studyMode;
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Text(
          requirementText,
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 13,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FilledButton.icon(
              onPressed: () async {
                final added = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => const MinistryEntryFormDialog(),
                );
                if (added == true && mounted) {
                  ref.read(ministryEntriesProvider.notifier).loadInitial();
                }
              },
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Add Ministry Entry'),
              style: FilledButton.styleFrom(
                backgroundColor: redColor,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: summaryListAsync.when(
            data: (rows) {
              if (rows.isEmpty) {
                return Center(
                  child: Text(
                    'No students in this category.',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 14,
                      fontFamily: 'Questrial',
                    ),
                  ),
                );
              }
              _summaryDataSource ??= MinistryHoursSummaryDataSource(
                rows: rows,
                colorScheme: colorScheme,
                requiredHours: requiredHours,
              );
              _summaryDataSource!.updateData(rows, requiredHours);
              return SfDataGrid(
                source: _summaryDataSource!,
                columnWidthMode: ColumnWidthMode.fill,
                gridLinesVisibility: GridLinesVisibility.horizontal,
                headerGridLinesVisibility: GridLinesVisibility.both,
                columns: [
                  GridColumn(
                    columnName: 'sn',
                    width: 60,
                    label: _buildHeader('S/N', colorScheme),
                  ),
                  GridColumn(
                    columnName: 'firstName',
                    width: 140,
                    label: _buildHeader('First Name', colorScheme),
                  ),
                  GridColumn(
                    columnName: 'lastName',
                    width: 140,
                    label: _buildHeader('Last Name', colorScheme),
                  ),
                  GridColumn(
                    columnName: 'term1',
                    width: 80,
                    label: _buildHeader('Term 1', colorScheme),
                  ),
                  GridColumn(
                    columnName: 'term2',
                    width: 80,
                    label: _buildHeader('Term 2', colorScheme),
                  ),
                  GridColumn(
                    columnName: 'term3',
                    width: 80,
                    label: _buildHeader('Term 3', colorScheme),
                  ),
                  GridColumn(
                    columnName: 'total',
                    width: 80,
                    label: _buildHeader('Total', colorScheme),
                  ),
                ],
              );
            },
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(
                'Error: $e',
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
    );
  }

  Widget _buildEntriesTab(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    MinistryEntriesState entriesState,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFiltersRow(context, colorScheme, redColor),
        const SizedBox(height: 16),
        Expanded(
          child: _buildTable(context, colorScheme, entriesState, redColor),
        ),
      ],
    );
  }

  Widget _buildStatCards(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    AsyncValue<MinistrySummaryStats> summaryAsync,
  ) {
    final stats = summaryAsync.valueOrNull;
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _statCard(
          colorScheme: colorScheme,
          title: 'Total Ministry Hours',
          value: stats != null ? _formatNumber(stats.totalHours) : '—',
          subtitle: 'Total hours recorded across all ministries.',
          valueColor: redColor,
          icon: Icons.access_time,
        ),
        _statCard(
          colorScheme: colorScheme,
          title: 'Avg Hours per Student',
          value: stats != null
              ? stats.avgHoursPerStudent.toStringAsFixed(1)
              : '—',
          subtitle: 'Average hours contributed by each student.',
          valueColor: colorScheme.onSurface,
          icon: Icons.person_outline,
        ),
        _statCard(
          colorScheme: colorScheme,
          title: 'Pending Approvals',
          value: stats != null ? '${stats.pendingApprovalsCount}' : '—',
          subtitle: 'Entries awaiting supervisor approval.',
          valueColor: colorScheme.onSurface,
          icon: Icons.pending_actions,
        ),
        _statCard(
          colorScheme: colorScheme,
          title: 'Approved Hours',
          value: stats != null ? _formatNumber(stats.approvedHours) : '—',
          subtitle: 'Hours officially approved by supervisors.',
          valueColor: colorScheme.onSurface,
          icon: Icons.check_circle_outline,
        ),
      ],
    );
  }

  String _formatNumber(double n) {
    if (n >= 1000) {
      return NumberFormat('#,###').format(n.round());
    }
    return n == n.roundToDouble() ? '${n.round()}' : n.toStringAsFixed(1);
  }

  Widget _statCard({
    required ColorScheme colorScheme,
    required String title,
    required String value,
    required String subtitle,
    required Color valueColor,
    required IconData icon,
    double width = 220,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontWeight: FontWeight.w700,
              fontSize: 28,
              fontFamily: 'Questrial',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontFamily: 'Questrial',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersRow(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
  ) {
    return Row(
      children: [
        SizedBox(
          width: 220,
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              hintText: 'Search entries...',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onSubmitted: (_) => _applyFilters(),
          ),
        ),
        const SizedBox(width: 12),
        DropdownButton<String?>(
          value: _selectedYear,
          hint: const Text('All Years'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('All Years')),
            ...List.generate(5, (i) => DateTime.now().year - 2 + i).map(
              (y) => DropdownMenuItem<String?>(
                value: '$y',
                child: Text('$y'),
              ),
            ),
          ],
          onChanged: (v) {
            setState(() => _selectedYear = v);
            _applyFilters();
          },
        ),
        const SizedBox(width: 12),
        DropdownButton<String?>(
          value: _selectedType,
          hint: const Text('All Types'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('All Types')),
            ...AppConstants.ministryTypeOptions.map(
              (t) => DropdownMenuItem<String?>(value: t, child: Text(t)),
            ),
          ],
          onChanged: (v) {
            setState(() => _selectedType = v);
            _applyFilters();
          },
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _pickDateRange,
          icon: const Icon(Icons.calendar_today, size: 18),
          label: Text(
            _dateFrom != null && _dateTo != null
                ? '${app_date_utils.DateUtils.formatIsoDate(_dateFrom!)} – ${app_date_utils.DateUtils.formatIsoDate(_dateTo!)}'
                : 'Date range',
          ),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: () async {
            final added = await showDialog<bool>(
              context: context,
              builder: (ctx) => const MinistryEntryFormDialog(),
            );
            if (added == true && mounted) {
              ref.read(ministryEntriesProvider.notifier).loadInitial();
            }
          },
          icon: const Icon(Icons.add, size: 20),
          label: const Text('Add Ministry Entry'),
          style: FilledButton.styleFrom(
            backgroundColor: redColor,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTable(
    BuildContext context,
    ColorScheme colorScheme,
    MinistryEntriesState entriesState,
    Color redColor,
  ) {
    if (entriesState.isLoading && entriesState.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    _dataSource ??= MinistryEntryDataSource(
      entries: entriesState.entries,
      colorScheme: colorScheme,
    );
    _dataSource!.updateData(entriesState.entries);

    if (entriesState.entries.isEmpty) {
      return Center(
        child: Text(
          'No ministry entries found.',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                final metrics = notification.metrics;
                if (metrics.pixels >= metrics.maxScrollExtent * 0.8) {
                  ref.read(ministryEntriesProvider.notifier).loadMore();
                }
              }
              return false;
            },
            child: SfDataGrid(
              source: _dataSource!,
              columnWidthMode: ColumnWidthMode.fill,
              gridLinesVisibility: GridLinesVisibility.horizontal,
              headerGridLinesVisibility: GridLinesVisibility.both,
              columns: [
                GridColumn(
                  columnName: 'sn',
                  width: 60,
                  label: _buildHeader('S/N', colorScheme),
                ),
                GridColumn(
                  columnName: 'name',
                  width: 180,
                  label: _buildHeader('Surname, Names', colorScheme),
                ),
                GridColumn(
                  columnName: 'year',
                  width: 80,
                  label: _buildHeader('Year', colorScheme),
                ),
                GridColumn(
                  columnName: 'type',
                  width: 140,
                  label: _buildHeader('Ministry Type', colorScheme),
                ),
                GridColumn(
                  columnName: 'date',
                  width: 110,
                  label: _buildHeader('Date', colorScheme),
                ),
                GridColumn(
                  columnName: 'hours',
                  width: 70,
                  label: _buildHeader('Hours', colorScheme),
                ),
                GridColumn(
                  columnName: 'supervisor',
                  width: 100,
                  label: _buildHeader('Supervisor', colorScheme),
                ),
                GridColumn(
                  columnName: 'approved',
                  width: 100,
                  label: _buildHeader('Approved', colorScheme),
                ),
                GridColumn(
                  columnName: 'notes',
                  width: double.nan,
                  label: _buildHeader('Notes', colorScheme),
                ),
              ],
            ),
          ),
        ),
        if (entriesState.isLoadingMore)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'Showing 1 to ${entriesState.entries.length} of ${entriesState.totalCount} entries',
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontFamily: 'Questrial',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(String text, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.all(12),
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
    );
  }
}

/// Data source for ministry hours summary grid (one row per student, Term 1/2/3/Total).
class MinistryHoursSummaryDataSource extends DataGridSource {
  MinistryHoursSummaryDataSource({
    required List<MinistryHoursSummaryRow> rows,
    required ColorScheme colorScheme,
    required int requiredHours,
  })  : _rows = rows,
        _colorScheme = colorScheme,
        _requiredHours = requiredHours {
    _buildRows();
  }

  List<MinistryHoursSummaryRow> _rows;
  final ColorScheme _colorScheme;
  int _requiredHours;

  void updateData(List<MinistryHoursSummaryRow> rows, int requiredHours) {
    _rows = rows;
    _requiredHours = requiredHours;
    _buildRows();
    notifyListeners();
  }

  void _buildRows() {
    _dataGridRows = _rows.asMap().entries.map((e) {
      final i = e.key + 1;
      final row = e.value;
      return DataGridRow(
        cells: [
          DataGridCell<int>(columnName: 'sn', value: i),
          DataGridCell<String>(columnName: 'firstName', value: row.firstName),
          DataGridCell<String>(columnName: 'lastName', value: row.lastName),
          DataGridCell<double>(columnName: 'term1', value: row.term1Hours),
          DataGridCell<double>(columnName: 'term2', value: row.term2Hours),
          DataGridCell<double>(columnName: 'term3', value: row.term3Hours),
          DataGridCell<double>(columnName: 'total', value: row.totalHours),
        ],
      );
    }).toList();
  }

  List<DataGridRow> _dataGridRows = [];

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final cells = row.getCells();
    final term1Cells = cells.where((c) => c.columnName == 'term1');
    final term2Cells = cells.where((c) => c.columnName == 'term2');
    final term1 = term1Cells.isEmpty ? null : term1Cells.first.value as double?;
    final term2 = term2Cells.isEmpty ? null : term2Cells.first.value as double?;
    final belowRequirement = (term1 != null && term1 < _requiredHours) ||
        (term2 != null && term2 < _requiredHours);
    final rowColor = belowRequirement
        ? _colorScheme.errorContainer.withValues(alpha: 0.3)
        : null;

    return DataGridRowAdapter(
      color: rowColor,
      cells: cells.map((cell) {
        Widget child;
        switch (cell.columnName) {
          case 'sn':
            child = Text(
              '${cell.value}',
              style: TextStyle(
                color: _colorScheme.onSurface,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            );
            break;
          case 'firstName':
          case 'lastName':
            child = Text(
              cell.value?.toString() ?? '',
              style: TextStyle(
                color: _colorScheme.onSurface,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
              overflow: TextOverflow.ellipsis,
            );
            break;
          case 'term1':
          case 'term2':
          case 'term3':
          case 'total':
            final n = cell.value as double;
            child = Text(
              n == n.roundToDouble() ? '${n.round()}' : n.toStringAsFixed(1),
              style: TextStyle(
                color: _colorScheme.onSurface,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            );
            break;
          default:
            child = const SizedBox();
        }
        return Container(
          padding: const EdgeInsets.all(8),
          alignment: Alignment.centerLeft,
          child: child,
        );
      }).toList(),
    );
  }
}

/// Data source for ministry entries grid.
class MinistryEntryDataSource extends DataGridSource {
  MinistryEntryDataSource({
    required List<MinistryEntryWithStudent> entries,
    required ColorScheme colorScheme,
  })  : _entries = entries,
        _colorScheme = colorScheme {
    _buildRows();
  }

  List<MinistryEntryWithStudent> _entries;
  final ColorScheme _colorScheme;
  List<DataGridRow> _dataGridRows = [];

  void updateData(List<MinistryEntryWithStudent> entries) {
    _entries = entries;
    _buildRows();
    notifyListeners();
  }

  void _buildRows() {
    _dataGridRows = _entries.asMap().entries.map((e) {
      final i = e.key + 1;
      final row = e.value;
      final entry = row.entry;
      return DataGridRow(cells: [
        DataGridCell<int>(columnName: 'sn', value: i),
        DataGridCell<String>(
            columnName: 'name', value: row.studentDisplayName,),
        DataGridCell<String>(columnName: 'year', value: entry.year),
        DataGridCell<String>(
            columnName: 'type', value: entry.ministryType,),
        DataGridCell<DateTime>(columnName: 'date', value: entry.date),
        DataGridCell<double>(columnName: 'hours', value: entry.hours),
        DataGridCell<String?>(
            columnName: 'supervisor', value: entry.supervisor ?? 'N/A',),
        DataGridCell<bool>(columnName: 'approved', value: entry.approved),
        DataGridCell<String?>(columnName: 'notes', value: entry.notes,),
      ],);
    }).toList();
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    return DataGridRowAdapter(
      cells: row.getCells().map((cell) {
        Widget child;
        switch (cell.columnName) {
          case 'sn':
            child = Text(
              '${cell.value}',
              style: TextStyle(
                color: _colorScheme.onSurface,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            );
            break;
          case 'name':
          case 'year':
          case 'type':
          case 'supervisor':
          case 'notes':
            child = Text(
              cell.value?.toString() ?? '',
              style: TextStyle(
                color: _colorScheme.onSurface,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
              overflow: TextOverflow.ellipsis,
            );
            break;
          case 'date':
            child = Text(
              app_date_utils.DateUtils.formatIsoDate(cell.value as DateTime),
              style: TextStyle(
                color: _colorScheme.onSurface,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            );
            break;
          case 'hours':
            child = Text(
              (cell.value as double).toStringAsFixed(1),
              style: TextStyle(
                color: _colorScheme.onSurface,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            );
            break;
          case 'approved':
            final approved = cell.value as bool;
            child = Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: approved
                    ? AppColors.syncedGreen.withValues(alpha: 0.2)
                    : _colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                approved ? 'Approved' : 'Pending',
                style: TextStyle(
                  color: approved
                      ? AppColors.syncedGreen
                      : _colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'Questrial',
                ),
              ),
            );
            break;
          default:
            child = const SizedBox();
        }
        return Container(
          padding: const EdgeInsets.all(8),
          alignment: Alignment.centerLeft,
          child: child,
        );
      }).toList(),
    );
  }
}
