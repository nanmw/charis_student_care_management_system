import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_datagrid/datagrid.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:go_router/go_router.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/mission_location_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:charis_student_care/presentation/widgets/mission_location_form_dialog.dart';

/// Mission Locations management screen: list locations with add/edit/delete.
class MissionLocationsScreen extends ConsumerStatefulWidget {
  const MissionLocationsScreen({super.key});

  @override
  ConsumerState<MissionLocationsScreen> createState() =>
      _MissionLocationsScreenState();
}

class _MissionLocationsScreenState extends ConsumerState<MissionLocationsScreen> {
  MissionLocationDataSource? _dataSource;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final locationsAsync = ref.watch(missionLocationsStreamProvider);

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
                'Mission Locations',
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
                      onPressed: () => context.go('/reports?type=mission-locations'),
                      icon: const Icon(Icons.download_outlined, size: 18),
                      label: const Text('Export'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  RoleGuard(
                    canShow: RolePermissions.canManageMissions,
                    child: ElevatedButton.icon(
                      onPressed: () => _openAddLocation(context),
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('Add Location'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: redColor,
                    foregroundColor: AppColors.charisWhite,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                  ),
                ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: locationsAsync.when(
              data: (locations) {
                if (locations.isEmpty) {
                  return Center(
                    child: Text(
                      'No mission locations found. Add a location to get started.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontFamily: 'Questrial',
                      ),
                    ),
                  );
                }
                _dataSource ??= MissionLocationDataSource(
                  locations: locations,
                  colorScheme: colorScheme,
                  onEdit: (loc) => _openEditLocation(context, loc),
                  onDelete: (loc) => _deleteLocation(context, loc),
                  canManage: RolePermissions.canManageMissions(
                    (ref.read(authStateProvider).valueOrNull
                            as Authenticated?)
                        ?.role ??
                        UserRole.facilitator,
                  ),
                );
                _dataSource!.updateData(
                  locations,
                  colorScheme,
                  (
                    (loc) => _openEditLocation(context, loc),
                    (loc) => _deleteLocation(context, loc),
                    RolePermissions.canManageMissions(
                      (ref.read(authStateProvider).valueOrNull
                              as Authenticated?)
                          ?.role ??
                          UserRole.facilitator,
                    ),
                  ),
                );
                return ClipRRect(
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
                        width: 200,
                        label: Container(
                          padding: const EdgeInsets.all(8),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Name',
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
                        columnName: 'description',
                        width: double.nan,
                        label: Container(
                          padding: const EdgeInsets.all(8),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Description',
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
                        columnName: 'active',
                        width: 100,
                        label: Container(
                          padding: const EdgeInsets.all(8),
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Active',
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
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Text(
                  'Error loading locations: $err',
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

  void _openAddLocation(BuildContext context) {
    MissionLocationFormDialog.showAdd(
      context: context,
      ref: ref,
      onSaved: () {},
    );
  }

  void _openEditLocation(BuildContext context, MissionLocation location) {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return;
    if (!RolePermissions.canManageMissions(auth.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'You do not have permission to edit mission locations',
              ),
            ),
      );
      return;
    }
    MissionLocationFormDialog.showEdit(
      context: context,
      ref: ref,
      location: location,
      onSaved: () {},
    );
  }

  Future<void> _deleteLocation(
      BuildContext context,
      MissionLocation location,
    ) async {
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return;
    if (!RolePermissions.canManageMissions(auth.role)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'You do not have permission to delete mission locations',
              ),
            ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
            'Delete Location',
            style: TextStyle(fontFamily: 'Questrial'),
          ),
        content: Text(
          'Are you sure you want to delete "${location.name}"?',
          style: const TextStyle(fontFamily: 'Questrial'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',),
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
        await ref.read(missionLocationRepositoryProvider).deleteMissionLocation(
              location.id,
              userRole: auth.role,
              userId: auth.user.id,
              userDisplayName: auth.user.displayName,
              screen: 'Mission Locations',
            );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location deleted successfully')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting location: $e')),
          );
        }
      }
    }
  }
}

class MissionLocationDataSource extends DataGridSource {
  MissionLocationDataSource({
    required List<MissionLocation> locations,
    required ColorScheme colorScheme,
    required void Function(MissionLocation) onEdit,
    required void Function(MissionLocation) onDelete,
    required bool canManage,
  })  : _locations = locations,
        _colorScheme = colorScheme,
        _onEdit = onEdit,
        _onDelete = onDelete,
        _canManage = canManage {
    _buildRows();
  }

  List<MissionLocation> _locations;
  ColorScheme _colorScheme;
  void Function(MissionLocation) _onEdit;
  void Function(MissionLocation) _onDelete;
  bool _canManage;

  List<DataGridRow> _dataGridRows = [];

  void updateData(
    List<MissionLocation> locations,
    ColorScheme colorScheme,
    (void Function(MissionLocation), void Function(MissionLocation), bool)
        callbacks,
  ) {
    _locations = locations;
    _colorScheme = colorScheme;
    _onEdit = callbacks.$1;
    _onDelete = callbacks.$2;
    _canManage = callbacks.$3;
    _buildRows();
    notifyListeners();
  }

  void _buildRows() {
    _dataGridRows = _locations
        .asMap()
        .entries
        .map((e) => DataGridRow(cells: [
              DataGridCell<int>(columnName: 'sn', value: e.key + 1),
              DataGridCell<String>(columnName: 'name', value: e.value.name),
              DataGridCell<String>(
                columnName: 'description',
                value: e.value.description ?? '—',
              ),
              DataGridCell<String>(
                columnName: 'active',
                value: e.value.isActive ? 'Yes' : 'No',
              ),
              DataGridCell<MissionLocation>(
                columnName: 'actions',
                value: e.value,
              ),
            ],
          ),
        )
        .toList();
  }

  @override
  List<DataGridRow> get rows => _dataGridRows;

  @override
  DataGridRowAdapter? buildRow(DataGridRow row) {
    final cells = row.getCells();
    final location =
        cells.firstWhere((c) => c.columnName == 'actions').value
            as MissionLocation;
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
                      onPressed: () => _onEdit(location),
                      icon: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: _colorScheme.onSurfaceVariant,
                      ),
                      label: Text(
                        'Edit',
                        style: TextStyle(
                          color: _colorScheme.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    TextButton.icon(
                      onPressed: () => _onDelete(location),
                      icon: Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: _colorScheme.error,
                      ),
                      label: Text(
                        'Delete',
                        style: TextStyle(
                          color: _colorScheme.error,
                          fontSize: 13,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
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
