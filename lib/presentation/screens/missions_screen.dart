import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/core/utils/currency_utils.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/mission_repository.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/mission_providers.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/theme/app_table_style.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:charis_student_care/presentation/widgets/mission_form_dialog.dart';
import 'package:charis_student_care/presentation/widgets/mission_signup_dialog.dart';
import 'package:charis_student_care/presentation/providers/academic_session_providers.dart';

/// Missions Overview screen: mission cards grid + Student Participation table.
class MissionsScreen extends ConsumerStatefulWidget {
  const MissionsScreen({super.key});

  @override
  ConsumerState<MissionsScreen> createState() => _MissionsScreenState();
}

String _formatMissionDateRange(DateTime start, DateTime end) {
  final f = DateFormat('MMM d');
  final sameYear = start.year == end.year;
  if (sameYear) {
    return '${f.format(start)} - ${f.format(end)}, ${end.year}';
  }
  return '${f.format(start)}, ${start.year} - ${f.format(end)}, ${end.year}';
}

class _MissionsScreenState extends ConsumerState<MissionsScreen> {
  String? _selectedYear; // null = All sessions
  bool _activeOnly = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final missionsAsync = ref.watch(
        missionsStreamProvider((year: _selectedYear, activeOnly: _activeOnly)),);
    final participationsAsync = ref.watch(missionParticipationsStreamProvider);

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Missions Overview',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 24,
                    fontFamily: 'Questrial',
                  ),
                ),
                Row(
                  children: [
                    _buildYearDropdown(colorScheme),
                    const SizedBox(width: 16),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Active Missions Only',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontSize: 14,
                            fontFamily: 'Questrial',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: _activeOnly,
                          onChanged: (v) => setState(() => _activeOnly = v),
                          activeTrackColor: redColor,
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    RoleGuard(
                      canShow: RolePermissions.canManageMissions,
                      child: ElevatedButton.icon(
                        onPressed: () => _openCreateMission(context),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Create Mission'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: redColor,
                          foregroundColor: AppColors.charisWhite,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12,),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Mission Opportunities',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 18,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 12),
            missionsAsync.when(
              data: (missions) {
                return participationsAsync.when(
                  data: (participationRows) {
                    return _buildMissionCards(
                      context,
                      missions,
                      participationRows,
                      redColor,
                      colorScheme,
                    );
                  },
                  loading: () => _buildMissionCards(
                    context,
                    missions,
                    [],
                    redColor,
                    colorScheme,
                  ),
                  error: (e, _) => _buildMissionCards(
                    context,
                    missions,
                    [],
                    redColor,
                    colorScheme,
                  ),
                );
              },
              loading: () => const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),),),
              error: (err, _) => Center(
                child: Text(
                  'Error loading missions: $err',
                  style: TextStyle(
                    color: colorScheme.error,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              'Student Participation',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
                fontSize: 18,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 12),
            participationsAsync.when(
              data: (rows) {
                final classesAsync = ref.watch(allClassesFutureProvider);
                return classesAsync.when(
                  data: (classes) {
                    final classIdToName = {
                      for (final c in classes) c.id: c.name,
                    };
                    return _buildParticipationTable(
                        context, rows, classIdToName,);
                  },
                  loading: () =>
                      _buildParticipationTable(context, rows, null),
                  error: (e, _) =>
                      _buildParticipationTable(context, rows, null),
                );
              },
              loading: () => const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: CircularProgressIndicator(),),),
              error: (err, _) => Center(
                child: Text(
                  'Error loading participations: $err',
                  style: TextStyle(
                    color: colorScheme.error,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYearDropdown(ColorScheme colorScheme) {
    final sessionOptionsAsync = ref.watch(academicSessionOptionsProvider);
    final currentSessionAsync = ref.watch(currentAcademicSessionProvider);

    return Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: sessionOptionsAsync.when(
        data: (options) {
          final currentSession = currentSessionAsync.valueOrNull;
          var list = options;
          if (list.isEmpty) {
            // Fallback to current calendar year string if no sessions exist yet.
            final fallback = DateTime.now().year.toString();
            list = [fallback];
          }

          String? selected = _selectedYear;
          if (selected != null && !list.contains(selected)) {
            selected = null;
          }

          if (selected == null && currentSession != null && list.contains(currentSession)) {
            selected = currentSession;
          }

          // Persist any inferred selection back into state.
          if (selected != _selectedYear) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _selectedYear = selected);
              }
            });
          }

          return DropdownButton<String?>(
            value: selected,
            isExpanded: true,
            underline: const SizedBox(),
            hint: const Text(
              'All sessions',
              style: TextStyle(fontSize: 14, fontFamily: 'Questrial'),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('All sessions'),
              ),
              ...list.map((session) {
                return DropdownMenuItem<String?>(
                  value: session,
                  child: Text(
                    session,
                    style: const TextStyle(
                      fontSize: 14,
                      fontFamily: 'Questrial',
                    ),
                  ),
                );
              }),
            ],
            onChanged: (value) => setState(() => _selectedYear = value),
          );
        },
        loading: () => DropdownButton<String?>(
          value: _selectedYear,
          isExpanded: true,
          underline: const SizedBox(),
          items: [
            DropdownMenuItem<String?>(
              value: _selectedYear,
              child: Text(
                _selectedYear ?? 'Loading...',
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
            ),
          ],
          onChanged: null,
        ),
        error: (_, __) => DropdownButton<String?>(
          value: _selectedYear,
          isExpanded: true,
          underline: const SizedBox(),
          items: [
            DropdownMenuItem<String?>(
              value: _selectedYear,
              child: Text(
                _selectedYear ?? 'Session unavailable',
                style: const TextStyle(
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
            ),
          ],
          onChanged: null,
        ),
      ),
    );
  }

  Widget _buildMissionCards(
    BuildContext context,
    List<Mission> missions,
    List<MissionParticipationRow> participationRows,
    Color redColor,
    ColorScheme colorScheme,
  ) {
    if (missions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No missions found. Create a mission to get started.',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const crossAxisCount = 2;
        const spacing = 16.0;
        final width = (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
            crossAxisCount;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: missions.map((mission) {
            final count = participationRows
                .where((r) => r.participation.missionId == mission.id)
                .length;
            final slotsAvailable =
                (mission.slotsTotal - count).clamp(0, mission.slotsTotal);
            return SizedBox(
              width: width,
              child: _MissionCard(
                mission: mission,
                slotsAvailable: slotsAvailable,
                redColor: redColor,
                colorScheme: colorScheme,
                onSignUp: () => _openSignUp(context, mission),
                onEdit: () => _openEditMission(context, mission),
                canManage: RolePermissions.canManageMissions(
                  (ref.read(authStateProvider).valueOrNull as Authenticated?)
                          ?.role ??
                      UserRole.facilitator,
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildParticipationTable(
    BuildContext context,
    List<MissionParticipationRow> rows, [
    Map<int, String>? classIdToName,
  ]) {
    final colorScheme = Theme.of(context).colorScheme;
    final auth = ref.read(authStateProvider).valueOrNull;
    final canManage =
        auth is Authenticated && RolePermissions.canManageMissions(auth.role);
    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No student participations yet.',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
      );
    }
    final dataSource = _ParticipationDataSource(
      rows: rows,
      colorScheme: colorScheme,
      classIdToName: classIdToName,
      onRemove: canManage ? (id) => _removeParticipation(context, id) : null,
      onRecordPayment:
          canManage ? (id) => _openRecordPayment(context, id) : null,
    );
    return SizedBox(
      height: 320,
      child: SfDataGrid(
        source: dataSource,
        columnWidthMode: ColumnWidthMode.fill,
        gridLinesVisibility: GridLinesVisibility.both,
        headerGridLinesVisibility: GridLinesVisibility.both,
        columns: [
            GridColumn(
              columnName: 'sn',
              width: 50,
              label: _gridHeader(context, 'S/N'),
            ),
            GridColumn(
              columnName: 'name',
              width: 140,
              label: _gridHeader(context, 'Surname, Names'),
            ),
            GridColumn(
              columnName: 'year',
              width: 70,
              label: _gridHeader(context, 'Year'),
            ),
            GridColumn(
              columnName: 'mission',
              width: 120,
              label: _gridHeader(context, 'Mission'),
            ),
            GridColumn(
              columnName: 'role',
              width: 100,
              label: _gridHeader(context, 'Role'),
            ),
            GridColumn(
              columnName: 'amount',
              width: 90,
              label: _gridHeader(context, 'Amount'),
            ),
            GridColumn(
              columnName: 'paid',
              width: 90,
              label: _gridHeader(context, 'Paid'),
            ),
            GridColumn(
              columnName: 'balance',
              width: 90,
              label: _gridHeader(context, 'Balance'),
            ),
            if (canManage)
              GridColumn(
                columnName: 'actions',
                width: 140,
                label: _gridHeader(context, 'Actions'),
              ),
          ],
      ),
    );
  }

  Widget _gridHeader(BuildContext context, String text) {
    return AppTableStyle.sfHeaderCell(context, text);
  }

  void _openCreateMission(BuildContext context) {
    MissionFormDialog.showAdd(
      context: context,
      ref: ref,
      onSaved: () {},
    );
  }

  void _openEditMission(BuildContext context, Mission mission) {
    MissionFormDialog.showEdit(
      context: context,
      ref: ref,
      mission: mission,
      onSaved: () {},
    );
  }

  void _openSignUp(BuildContext context, Mission mission) {
    final count = ref
            .read(participationsForMissionProvider(mission.id))
            .valueOrNull
            ?.length ??
        0;
    final slotsAvailable =
        (mission.slotsTotal - count).clamp(0, mission.slotsTotal);
    if (slotsAvailable <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No slots available for this mission')),
      );
      return;
    }
    MissionSignupDialog.show(
      context: context,
      ref: ref,
      mission: mission,
      slotsAvailable: slotsAvailable,
      onSaved: () {},
    );
  }

  Future<void> _removeParticipation(BuildContext context, int id) async {
    try {
      final auth = ref.read(authStateProvider).valueOrNull;
      final deviceId = await ref.read(deviceIdProvider.future);
      await ref.read(missionRepositoryProvider).removeParticipation(
            id,
            userRole: auth is Authenticated
                ? auth.role
                : UserRole.facilitator,
            userId: auth is Authenticated ? auth.user.id : null,
            deviceId: deviceId,
            userDisplayName:
                auth is Authenticated ? auth.user.displayName : null,
            screen: 'Missions',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Participation removed')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _openRecordPayment(
      BuildContext context, int participationId,) async {
    DateTime paymentDate = DateTime.now();
    final amountController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Record payment'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Payment date'),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: paymentDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => paymentDate = picked);
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      child: Text(DateFormat('yyyy-MM-dd').format(paymentDate)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Amount (R)'),
                  const SizedBox(height: 4),
                  TextField(
                    controller: amountController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Amount paid',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final amountStr = amountController.text.trim();
                    final amount = double.tryParse(amountStr);
                    if (amount == null || amount <= 0) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Enter a positive amount'),),
                      );
                      return;
                    }
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );
    if (saved != true || !context.mounted) return;
    final amountStr = amountController.text.trim();
    final amount = double.tryParse(amountStr) ?? 0;
    if (amount <= 0) return;
    try {
      final auth = ref.read(authStateProvider).valueOrNull;
      final deviceId = await ref.read(deviceIdProvider.future);
      final session =
          ref.read(currentAcademicSessionProvider).valueOrNull ?? _selectedYear;
      await ref.read(missionRepositoryProvider).addMissionPayment(
            participationId: participationId,
            paymentDate: paymentDate,
            amount: amount,
            userRole: auth is Authenticated
                ? auth.role
                : UserRole.facilitator,
            academicSession: session,
            userId: auth is Authenticated ? auth.user.id : null,
            deviceId: deviceId,
            userDisplayName:
                auth is Authenticated ? auth.user.displayName : null,
            screen: 'Missions',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment recorded')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

class _MissionCard extends StatelessWidget {
  const _MissionCard({
    required this.mission,
    required this.slotsAvailable,
    required this.redColor,
    required this.colorScheme,
    required this.onSignUp,
    required this.onEdit,
    required this.canManage,
  });

  final Mission mission;
  final int slotsAvailable;
  final Color redColor;
  final ColorScheme colorScheme;
  final VoidCallback onSignUp;
  final VoidCallback onEdit;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    mission.title,
                    style: TextStyle(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                      fontFamily: 'Questrial',
                    ),
                  ),
                ),
                if (canManage)
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: onEdit,
                    tooltip: 'Edit mission',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.location_on_outlined,
                    size: 16, color: colorScheme.onSurfaceVariant,),
                const SizedBox(width: 4),
                Text(
                  mission.location,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined,
                    size: 16, color: colorScheme.onSurfaceVariant,),
                const SizedBox(width: 4),
                Text(
                  _formatMissionDateRange(mission.startDate, mission.endDate),
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.people_outline,
                    size: 16, color: colorScheme.onSurfaceVariant,),
                const SizedBox(width: 4),
                Text(
                  '$slotsAvailable slots available',
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ],
            ),
            if (mission.description != null &&
                mission.description!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                mission.description!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: slotsAvailable > 0 ? onSignUp : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: redColor,
                  foregroundColor: AppColors.charisWhite,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Sign-up'),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward,
                        size: 18, color: AppColors.charisWhite,),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipationDataSource extends DataGridSource {
  _ParticipationDataSource({
    required List<MissionParticipationRow> rows,
    required ColorScheme colorScheme,
    Map<int, String>? classIdToName,
    void Function(int id)? onRemove,
    void Function(int id)? onRecordPayment,
  })  : _rows = rows,
        _colorScheme = colorScheme,
        _classIdToName = classIdToName ?? {},
        _onRemove = onRemove,
        _onRecordPayment = onRecordPayment {
    _buildDataGridRows();
  }

  final List<MissionParticipationRow> _rows;
  final ColorScheme _colorScheme;
  final Map<int, String> _classIdToName;
  final void Function(int id)? _onRemove;
  final void Function(int id)? _onRecordPayment;
  List<DataGridRow> _dataGridRows = [];

  void _buildDataGridRows() {
    _dataGridRows = _rows.asMap().entries.map((entry) {
      final i = entry.key + 1;
      final r = entry.value;
      final yearLabel = r.student.classId != null
          ? (_classIdToName[r.student.classId] ?? '—')
          : '—';
      return DataGridRow(cells: [
        DataGridCell<int>(columnName: 'sn', value: i),
        DataGridCell<String>(
            columnName: 'name',
            value: '${r.student.surname}, ${r.student.firstName}',),
        DataGridCell<String>(columnName: 'year', value: yearLabel),
        DataGridCell<String>(columnName: 'mission', value: r.mission.title),
        DataGridCell<String>(columnName: 'role', value: r.participation.role),
        DataGridCell<String>(
            columnName: 'amount',
            value: CurrencyUtils.formatRand(r.participation.amount),),
        DataGridCell<String>(
            columnName: 'paid', value: CurrencyUtils.formatRand(r.paidToDate),),
        DataGridCell<String>(
            columnName: 'balance', value: CurrencyUtils.formatRand(r.balance),),
        if (_onRemove != null || _onRecordPayment != null)
          DataGridCell<int>(columnName: 'actions', value: r.participation.id),
      ],);
    }).toList();
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter buildRow(DataGridRow row) {
    final cells = row.getCells();
    final widgetCells = <Widget>[];
    for (var i = 0; i < cells.length; i++) {
      final cell = cells[i];
      if (cell.columnName == 'actions' && cell.value != null) {
        final id = cell.value as int;
        widgetCells.add(
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_onRecordPayment != null)
                  TextButton(
                    onPressed: () => _onRecordPayment!(id),
                    child: Text(
                      'Record payment',
                      style: TextStyle(
                        color: _colorScheme.primary,
                        fontSize: 13,
                        fontFamily: 'Questrial',
                      ),
                    ),
                  ),
                if (_onRemove != null)
                  TextButton(
                    onPressed: () => _onRemove!(id),
                    child: Text(
                      'Remove',
                      style: TextStyle(
                        color: _colorScheme.error,
                        fontSize: 13,
                        fontFamily: 'Questrial',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      } else {
        widgetCells.add(
          Container(
            padding: AppTableStyle.cellPadding,
            alignment: Alignment.centerLeft,
            child: Text(
              cell.value?.toString() ?? '',
              style: AppTableStyle.bodyTextStyle(_colorScheme),
            ),
          ),
        );
      }
    }
    return DataGridRowAdapter(cells: widgetCells);
  }
}
