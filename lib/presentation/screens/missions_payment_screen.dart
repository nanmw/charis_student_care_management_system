import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:go_router/go_router.dart';
import 'package:charis_student_care/core/utils/currency_utils.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/mission_payment_repository.dart';
import 'package:charis_student_care/domain/use_cases/sort_students_alphabetically.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/facilitator_scope_provider.dart';
import 'package:charis_student_care/data/repositories/academic_session_repository.dart';
import 'package:charis_student_care/presentation/providers/academic_session_providers.dart';
import 'package:charis_student_care/presentation/providers/mission_location_providers.dart';
import 'package:charis_student_care/presentation/providers/mission_payment_providers.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/widgets/searchable_dropdown.dart';

/// Mission schedule month columns (Mar–Oct).
const List<String> _monthLabels = [
  'MARCH',
  'APRIL',
  'MAY',
  'JUNE',
  'JULY',
  'AUG',
  'SEPT',
  'OCT',
];

/// Sentinel value for "Other (custom)..." in Trip Selected dropdown; never stored.
const String _otherTripSentinel = '__other__';

/// One row's editable state for mission payment schedule.
class _MissionRowEdit {
  _MissionRowEdit({
    this.tripSelected,
    this.date,
    this.amount = 0,
    this.mar = 0,
    this.apr = 0,
    this.may = 0,
    this.jun = 0,
    this.jul = 0,
    this.aug = 0,
    this.sep = 0,
    this.oct = 0,
    this.comment,
  });

  String? tripSelected;
  DateTime? date;
  double amount;
  double mar;
  double apr;
  double may;
  double jun;
  double jul;
  double aug;
  double sep;
  double oct;
  String? comment;

  double get paidToDate => mar + apr + may + jun + jul + aug + sep + oct;
  double get balance => amount - paidToDate;

  String get paidToDateFormatted => CurrencyUtils.formatRand(paidToDate);
  String get balanceFormatted => CurrencyUtils.formatRand(balance);
}

/// Editable numeric cell for mission table.
class _MissionNumericCell extends StatefulWidget {
  const _MissionNumericCell({
    required this.controller,
    required this.colorScheme,
    required this.onChanged,
    required this.isDark,
    this.width = 70,
  });

  final TextEditingController controller;
  final ColorScheme colorScheme;
  final void Function(double) onChanged;
  final bool isDark;
  final double width;

  @override
  State<_MissionNumericCell> createState() => _MissionNumericCellState();
}

class _MissionNumericCellState extends State<_MissionNumericCell> {
  Timer? _debounceTimer;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: widget.width,
        child: TextField(
          controller: widget.controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: TextStyle(
              color: widget.colorScheme.onSurfaceVariant,
              fontSize: 13,
            ),
            border: InputBorder.none,
            filled: true,
            fillColor:
                widget.isDark ? AppColors.surfaceDark : AppColors.charisWhite,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            isDense: true,
          ),
          style: TextStyle(
            color: widget.colorScheme.onSurface,
            fontSize: 13,
          ),
          onChanged: (v) {
            final n = double.tryParse(v);
            if (n != null && n >= 0) {
              _debounceTimer?.cancel();
              _debounceTimer = Timer(const Duration(milliseconds: 300), () {
                widget.onChanged(n);
              });
            }
          },
        ),
      ),
    );
  }
}

/// Display-only text cell.
class _MissionDisplayCell extends StatelessWidget {
  const _MissionDisplayCell({
    required this.text,
    required this.colorScheme,
    this.textColor,
  });

  final String text;
  final ColorScheme colorScheme;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Text(
        text,
        style: TextStyle(
          color: textColor ?? colorScheme.onSurface,
          fontSize: 14,
          fontFamily: 'Questrial',
        ),
      ),
    );
  }
}

String _formatDate(DateTime? d) {
  if (d == null) return '';
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

class MissionsPaymentScreen extends ConsumerStatefulWidget {
  const MissionsPaymentScreen({super.key});

  @override
  ConsumerState<MissionsPaymentScreen> createState() =>
      _MissionsPaymentScreenState();
}

String _defaultMissionSession() {
  final now = DateTime.now();
  final y = now.year;
  return now.month >= 7 ? '$y-${y + 1}' : '${y - 1}-$y';
}

class _MissionsPaymentScreenState extends ConsumerState<MissionsPaymentScreen> {
  String _selectedMode = 'Full-time';
  String _scheduleSession = _defaultMissionSession();
  String _searchQuery = '';
  final Map<String, Map<int, _MissionRowEdit>> _editsBySession = {};
  final Map<String, TextEditingController> _controllers = {};
  String _refillKey = '';
  final ScrollController _scrollController = ScrollController();
  final Set<String> _customTripNames = {};

  Map<int, _MissionRowEdit> get _currentEdits {
    return _editsBySession.putIfAbsent(_scheduleSession, () => {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _buildModeToggle(ColorScheme colorScheme, Color redColor) {
    final modeOptions = ref.watch(modeOptionsForCurrentUserProvider);
    if (modeOptions.length == 1) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: redColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: redColor),
        ),
        child: Text(
          modeOptions[0],
          style: TextStyle(
            fontFamily: 'Questrial',
            fontSize: 14,
            color: colorScheme.onSurface,
          ),
        ),
      );
    }
    return ToggleButtons(
      constraints: const BoxConstraints(minWidth: 120, minHeight: 44),
      borderRadius: BorderRadius.circular(8),
      fillColor: redColor,
      selectedColor: AppColors.charisWhite,
      color: colorScheme.onSurface,
      isSelected: modeOptions.map((m) => m == _selectedMode).toList(),
      onPressed: (index) {
        setState(() => _selectedMode = modeOptions[index]);
      },
      children: modeOptions
          .map(
            (l) => Text(
              l,
              style: const TextStyle(
                fontFamily: 'Questrial',
                fontSize: 14,
              ),
            ),
          )
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final modeOptions = ref.watch(modeOptionsForCurrentUserProvider);
    if (modeOptions.length == 1 && _selectedMode != modeOptions[0]) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedMode = modeOptions[0]);
      });
    }
    final studentsAsync = ref.watch(studentsStreamProvider('Active'));
    final scheduleAsync =
        ref.watch(missionPaymentsForSessionStreamProvider(_scheduleSession));
    final locationsAsync = ref.watch(missionLocationsStreamProvider);

    return RoleGuard(
      canShow: (role) => RolePermissions.canManageFinancials(role),
      placeholder: Center(
        child: Text(
          'You do not have permission to view or manage missions payments.',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
      ),
      child: Container(
        color: colorScheme.surface,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _buildHeader(colorScheme)),
                RoleGuard(
                  canShow: RolePermissions.canExportReports,
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/reports?type=missions-payment'),
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('Export'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'MISSIONS PAYMENT SCHEDULE $_scheduleSession',
              style: TextStyle(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                fontSize: 18,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 16),
            _buildFiltersRow(colorScheme, redColor),
            const SizedBox(height: 24),
            Expanded(
              child: studentsAsync.when(
                data: (allStudents) {
                  final year2Id = ref.watch(year2ClassIdProvider).valueOrNull;
                  final searchLower = _searchQuery.toLowerCase();
                  final filtered = allStudents.where((s) {
                    if (year2Id == null || s.classId != year2Id) return false;
                    if (s.mode != _selectedMode) return false;
                    if (searchLower.isNotEmpty) {
                      if (!s.surname.toLowerCase().contains(searchLower) &&
                          !s.firstName.toLowerCase().contains(searchLower)) {
                        return false;
                      }
                    }
                    return true;
                  }).toList();
                  final students = sortStudentsAlphabetically(filtered);

                  return scheduleAsync.when(
                    data: (rows) {
                      _refillEditsIfNeeded(students, rows);
                      final locations =
                          locationsAsync.valueOrNull ?? <MissionLocation>[];
                      final locationNames = locations
                          .where((l) => l.isActive)
                          .map((l) => l.name)
                          .toList();
                      final existingCustom = rows
                          .map((r) => r.tripSelected)
                          .whereType<String>()
                          .where((t) =>
                              t.isNotEmpty && !locationNames.contains(t),)
                          .toSet()
                          .toList();
                      final baseTripOptions = [
                        ...locationNames,
                        ...existingCustom,
                        ..._customTripNames,
                      ];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              OutlinedButton.icon(
                                onPressed: () => _exportCsv(students),
                                icon: const Icon(Icons.download, size: 20),
                                label: const Text('Export'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: colorScheme.onSurfaceVariant,
                                  side: BorderSide(color: colorScheme.outline),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: _save,
                                icon: const Icon(
                                  Icons.save,
                                  size: 20,
                                  color: AppColors.charisWhite,
                                ),
                                label: const Text(
                                  'Save',
                                  style: TextStyle(
                                    color: AppColors.charisWhite,
                                    fontFamily: 'Questrial',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: redColor,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 24,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: students.isEmpty
                                ? Center(
                                    child: Text(
                                      'No 2nd year $_selectedMode students.',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 14,
                                        fontFamily: 'Questrial',
                                      ),
                                    ),
                                  )
                                : _buildTable(
                                    context,
                                    colorScheme,
                                    redColor,
                                    isDark,
                                    students,
                                    baseTripOptions,
                                  ),
                          ),
                        ],
                      );
                    },
                    loading: () => Center(
                      child: CircularProgressIndicator(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    error: (err, _) => Center(
                      child: Text(
                        'Error loading schedule: $err',
                        style: TextStyle(
                          color: colorScheme.error,
                        ),
                      ),
                    ),
                  );
                },
                loading: () => Center(
                  child: CircularProgressIndicator(
                    color: colorScheme.onSurface,
                  ),
                ),
                error: (err, _) => Center(
                  child: Text(
                    'Error: $err',
                    style: TextStyle(
                      color: colorScheme.error,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Text(
      'CHARIS BIBLE COLLEGE - CAPE TOWN',
      style: TextStyle(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w700,
        fontSize: 24,
        fontFamily: 'Questrial',
      ),
    );
  }

  Widget _buildFiltersRow(ColorScheme colorScheme, Color redColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '2nd Year:',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(width: 8),
        _buildModeToggle(colorScheme, redColor),
        const SizedBox(width: 24),
        Text(
          'Session:',
          style: TextStyle(
            color: colorScheme.onSurfaceVariant,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(width: 8),
        _buildSessionDropdown(colorScheme),
        const SizedBox(width: 24),
        Expanded(
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v),
            decoration: InputDecoration(
              hintText: 'Search students...',
              hintStyle: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: colorScheme.onSurfaceVariant,
                size: 22,
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionDropdown(ColorScheme colorScheme) {
    final sessionOptionsAsync = ref.watch(academicSessionOptionsProvider);
    return SizedBox(
      width: 120,
      child: sessionOptionsAsync.when(
        data: (options) {
          final list = options.isNotEmpty ? options : [_defaultMissionSession()];
          final value = list.contains(_scheduleSession) ? _scheduleSession : list.first;
          if (!list.contains(_scheduleSession)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _scheduleSession = list.first);
            });
          }
          return Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colorScheme.outline),
            ),
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(8),
              items: list
                  .map(
                    (s) => DropdownMenuItem<String>(
                      value: s,
                      child: Text(
                        s,
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) setState(() => _scheduleSession = v);
              },
            ),
          );
        },
        loading: () => Container(
          height: 44,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outline),
          ),
          child: Text(
            _scheduleSession,
            style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
          ),
        ),
        error: (_, __) => Container(
          height: 44,
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colorScheme.outline),
          ),
          child: Text(
            _scheduleSession,
            style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
          ),
        ),
      ),
    );
  }

  void _refillEditsIfNeeded(
    List<Student> students,
    List<MissionPaymentScheduleData> rows,
  ) {
    final rowMap = {for (final r in rows) r.studentId: r};
    final key =
        '$_scheduleSession|${students.length}|${rows.length}|${students.map((s) => s.id).join(',')}';
    if (key == _refillKey) return;
    _refillKey = key;
    final edits = _currentEdits;

    for (final s in students) {
      final row = rowMap[s.id];
      if (!edits.containsKey(s.id)) {
        edits[s.id] = _MissionRowEdit(
          tripSelected: row?.tripSelected,
          date: row?.date != null
              ? DateTime.fromMillisecondsSinceEpoch(row!.date!)
              : null,
          amount: row?.amount ?? 0,
          mar: row?.mar ?? 0,
          apr: row?.apr ?? 0,
          may: row?.may ?? 0,
          jun: row?.jun ?? 0,
          jul: row?.jul ?? 0,
          aug: row?.aug ?? 0,
          sep: row?.sep ?? 0,
          oct: row?.oct ?? 0,
          comment: row?.comment,
        );
      }
    }

    final studentIds = students.map((s) => s.id).toSet();
    for (final k in _controllers.keys.toList()) {
      final id = int.tryParse(k.split('_').first);
      if (id == null || !studentIds.contains(id)) {
        _controllers[k]?.dispose();
        _controllers.remove(k);
      }
      if (k.endsWith('_trip')) {
        _controllers[k]?.dispose();
        _controllers.remove(k);
      }
    }

    for (final s in students) {
      final edit = edits[s.id]!;
      _ensureController('${s.id}_amount',
          edit.amount > 0 ? edit.amount.toStringAsFixed(0) : '',);
      for (var i = 0; i < _monthLabels.length; i++) {
        final vals = [
          edit.mar,
          edit.apr,
          edit.may,
          edit.jun,
          edit.jul,
          edit.aug,
          edit.sep,
          edit.oct,
        ];
        _ensureController(
            '${s.id}_m$i', vals[i] > 0 ? vals[i].toStringAsFixed(0) : '',);
      }
      _ensureController('${s.id}_comment', edit.comment ?? '');
    }
    if (mounted) setState(() {});
  }

  void _ensureController(String key, String value) {
    final c = _controllers[key] ??= TextEditingController();
    if (c.text != value) c.text = value;
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

  Future<String?> _showOtherTripDialog(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Other trip name'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Enter trip name',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
            onSubmitted: (_) => Navigator.of(context).pop(controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final v = controller.text.trim();
                Navigator.of(context).pop(v.isEmpty ? null : v);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTripDropdown({
    required BuildContext context,
    required ColorScheme colorScheme,
    required bool isDark,
    required double width,
    required List<String> baseTripOptions,
    required _MissionRowEdit edit,
    required int studentId,
    required Map<int, _MissionRowEdit> edits,
  }) {
    final current = edit.tripSelected;
    final optionSet = baseTripOptions.toSet();
    final options = [
      ...baseTripOptions,
      if (current != null &&
          current.isNotEmpty &&
          !optionSet.contains(current))
        current,
    ];
    final items = [...options, _otherTripSentinel];
    return SizedBox(
      width: width,
      child: SearchableDropdown<String>(
        items: items,
        selectedValue: (current != null && current.isNotEmpty) ? current : null,
        hint: '',
        searchHint: 'Search trips...',
        allowClear: true,
        itemBuilder: (context, item) => Text(
          item == _otherTripSentinel ? 'Other (custom)...' : item,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 13,
          ),
        ),
        displayTextBuilder: (value) =>
            value == _otherTripSentinel ? 'Other (custom)...' : value,
        onChanged: (v) async {
          if (!mounted) return;
          if (v == _otherTripSentinel) {
            final custom = await _showOtherTripDialog(context);
            if (custom != null && custom.isNotEmpty && mounted) {
              setState(() {
                _customTripNames.add(custom);
                (edits[studentId] ??= _MissionRowEdit()).tripSelected = custom;
              });
            }
          } else {
            setState(() {
              (edits[studentId] ??= _MissionRowEdit()).tripSelected = v;
            });
          }
        },
      ),
    );
  }

  Widget _buildTable(
    BuildContext context,
    ColorScheme colorScheme,
    Color redColor,
    bool isDark,
    List<Student> students,
    List<String> baseTripOptions,
  ) {
    final edits = _currentEdits;
    const colSn = 50.0;
    const colName = 100.0;
    const colSurname = 100.0;
    const colTrip = 180.0; // 120 + 50% (60)
    const colDate = 150.0; // 100 + 50% (50)
    const colAmount = 80.0;
    const colMonth = 70.0;
    const colPaid = 90.0;
    const colBal = 90.0;
    const colComment = 140.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        return RepaintBoundary(
          child: SingleChildScrollView(
            controller: _scrollController,
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                columnWidths: Map.fromEntries([
                  const MapEntry(0, FixedColumnWidth(colSn)),
                  const MapEntry(1, FixedColumnWidth(colName)),
                  const MapEntry(2, FixedColumnWidth(colSurname)),
                  const MapEntry(3, FixedColumnWidth(colTrip)),
                  const MapEntry(4, FixedColumnWidth(colDate)),
                  const MapEntry(5, FixedColumnWidth(colAmount)),
                  ...List.generate(8,
                      (i) => MapEntry(6 + i, const FixedColumnWidth(colMonth)),),
                  const MapEntry(14, FixedColumnWidth(colPaid)),
                  const MapEntry(15, FixedColumnWidth(colBal)),
                  const MapEntry(16, FixedColumnWidth(colComment)),
                ]),
                border: TableBorder.all(color: colorScheme.outlineVariant),
                children: [
                  TableRow(
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                    ),
                    children: [
                      _tableHeader(context, 'S/N'),
                      _tableHeader(context, 'NAME'),
                      _tableHeader(context, 'SURNAME'),
                      _tableHeader(context, 'TRIP SELECTED'),
                      _tableHeader(context, 'DATE'),
                      _tableHeader(context, 'AMOUNT'),
                      ..._monthLabels.map((l) => _tableHeader(context, l)),
                      _tableHeader(context, 'PAID TO DATE'),
                      _tableHeader(context, 'BAL'),
                      _tableHeader(context, 'COMMENT'),
                    ],
                  ),
                  ...students.asMap().entries.map((entry) {
                    final index = entry.key;
                    final student = entry.value;
                    final edit = edits[student.id] ?? _MissionRowEdit();
                    final rowColor = index.isEven
                        ? colorScheme.surface
                        : colorScheme.surfaceContainerLow
                            .withValues(alpha: 0.5);

                    final amountCtrl = _controllers['${student.id}_amount'] ??=
                        TextEditingController();
                    if (amountCtrl.text !=
                        (edit.amount > 0
                            ? edit.amount.toStringAsFixed(0)
                            : '')) {
                      amountCtrl.text =
                          edit.amount > 0 ? edit.amount.toStringAsFixed(0) : '';
                    }

                    return TableRow(
                      decoration: BoxDecoration(color: rowColor),
                      children: [
                        _cell(
                            context,
                            colorScheme,
                            _MissionDisplayCell(
                                text: '${index + 1}',
                                colorScheme: colorScheme,),),
                        _cell(
                            context,
                            colorScheme,
                            _MissionDisplayCell(
                                text: student.firstName,
                                colorScheme: colorScheme,),),
                        _cell(
                            context,
                            colorScheme,
                            _MissionDisplayCell(
                                text: student.surname,
                                colorScheme: colorScheme,),),
                        _cell(
                          context,
                          colorScheme,
                          _buildTripDropdown(
                            context: context,
                            colorScheme: colorScheme,
                            isDark: isDark,
                            width: colTrip,
                            baseTripOptions: baseTripOptions,
                            edit: edit,
                            studentId: student.id,
                            edits: edits,
                          ),
                        ),
                        _cell(
                          context,
                          colorScheme,
                          SizedBox(
                            width: colDate,
                            child: InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: edit.date ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null && mounted) {
                                  setState(() {
                                    (edits[student.id] ??= _MissionRowEdit())
                                        .date = picked;
                                  });
                                }
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8,),
                                child: Text(
                                  _formatDate(edit.date),
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        _cell(
                          context,
                          colorScheme,
                          _MissionNumericCell(
                            controller: amountCtrl,
                            colorScheme: colorScheme,
                            isDark: isDark,
                            width: colAmount,
                            onChanged: (n) {
                              if (mounted) {
                                setState(() {
                                  (edits[student.id] ??= _MissionRowEdit())
                                      .amount = n;
                                });
                              }
                            },
                          ),
                        ),
                        ...List.generate(8, (i) {
                          final ctrl = _controllers['${student.id}_m$i'] ??=
                              TextEditingController();
                          final vals = [
                            edit.mar,
                            edit.apr,
                            edit.may,
                            edit.jun,
                            edit.jul,
                            edit.aug,
                            edit.sep,
                            edit.oct,
                          ];
                          if (ctrl.text !=
                              (vals[i] > 0 ? vals[i].toStringAsFixed(0) : '')) {
                            ctrl.text =
                                vals[i] > 0 ? vals[i].toStringAsFixed(0) : '';
                          }
                          return _cell(
                            context,
                            colorScheme,
                            _MissionNumericCell(
                              controller: ctrl,
                              colorScheme: colorScheme,
                              isDark: isDark,
                              width: colMonth,
                              onChanged: (n) {
                                if (mounted) {
                                  setState(() {
                                    final e =
                                        edits[student.id] ??= _MissionRowEdit();
                                    switch (i) {
                                      case 0:
                                        e.mar = n;
                                        break;
                                      case 1:
                                        e.apr = n;
                                        break;
                                      case 2:
                                        e.may = n;
                                        break;
                                      case 3:
                                        e.jun = n;
                                        break;
                                      case 4:
                                        e.jul = n;
                                        break;
                                      case 5:
                                        e.aug = n;
                                        break;
                                      case 6:
                                        e.sep = n;
                                        break;
                                      case 7:
                                        e.oct = n;
                                        break;
                                    }
                                  });
                                }
                              },
                            ),
                          );
                        }),
                        _cell(
                            context,
                            colorScheme,
                            _MissionDisplayCell(
                                text: edit.paidToDateFormatted,
                                colorScheme: colorScheme,),),
                        _cell(
                          context,
                          colorScheme,
                          _MissionDisplayCell(
                            text: edit.balanceFormatted,
                            colorScheme: colorScheme,
                            textColor: edit.balance > 0
                                ? colorScheme.error
                                : colorScheme.onSurface,
                          ),
                        ),
                        _cell(
                          context,
                          colorScheme,
                          SizedBox(
                            width: colComment,
                            child: TextField(
                              controller:
                                  _controllers['${student.id}_comment'] ??=
                                      TextEditingController(
                                          text: edit.comment ?? '',),
                              decoration: InputDecoration(
                                hintText: '',
                                border: InputBorder.none,
                                filled: true,
                                fillColor: isDark
                                    ? AppColors.surfaceDark
                                    : AppColors.charisWhite,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 8,),
                                isDense: true,
                              ),
                              style: TextStyle(
                                  color: colorScheme.onSurface, fontSize: 13,),
                              onChanged: (v) {
                                if (mounted) {
                                  setState(() {
                                    (edits[student.id] ??= _MissionRowEdit())
                                        .comment = v.isEmpty ? null : v;
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    try {
      final repo = ref.read(missionPaymentRepositoryProvider);
      final edits = _currentEdits;
      if (edits.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No mission payments to save.')),
          );
        }
        return;
      }

      final paymentDataMap = <int, MissionPaymentData>{};
      for (final entry in edits.entries) {
        final e = entry.value;
        paymentDataMap[entry.key] = MissionPaymentData(
          tripSelected: e.tripSelected,
          date: e.date,
          amount: e.amount,
          mar: e.mar,
          apr: e.apr,
          may: e.may,
          jun: e.jun,
          jul: e.jul,
          aug: e.aug,
          sep: e.sep,
          oct: e.oct,
          comment: e.comment,
        );
      }

      final sessionRepo = ref.read(academicSessionRepositoryProvider);
      final year = AcademicSessionRepository.yearFromSessionCode(_scheduleSession) ?? _scheduleSession.split('-').first;
      final academicSessionId = await sessionRepo.getSessionIdByCode(_scheduleSession);
      final count = await repo.batchUpsertMissionPayments(
        year: year,
        payments: paymentDataMap,
        academicSessionId: academicSessionId,
        userId: ref.read(authStateProvider).valueOrNull is Authenticated
            ? (ref.read(authStateProvider).valueOrNull as Authenticated).user.id
            : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved $count mission payment record(s).'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving: $e'),
          ),
        );
      }
    }
  }

  void _exportCsv(List<Student> students) {
    final edits = _currentEdits;
    final header = [
      'S/N',
      'NAME',
      'SURNAME',
      'TRIP SELECTED',
      'DATE',
      'AMOUNT',
      ..._monthLabels,
      'PAID TO DATE',
      'BAL',
      'COMMENT',
    ];
    final rows = <String>[header.join(',')];
    for (var i = 0; i < students.length; i++) {
      final s = students[i];
      final e = edits[s.id] ?? _MissionRowEdit();
      rows.add(
        [
          (i + 1).toString(),
          '"${s.firstName}"',
          '"${s.surname}"',
          '"${e.tripSelected ?? ''}"',
          _formatDate(e.date),
          e.amount.toStringAsFixed(0),
          e.mar.toStringAsFixed(0),
          e.apr.toStringAsFixed(0),
          e.may.toStringAsFixed(0),
          e.jun.toStringAsFixed(0),
          e.jul.toStringAsFixed(0),
          e.aug.toStringAsFixed(0),
          e.sep.toStringAsFixed(0),
          e.oct.toStringAsFixed(0),
          e.paidToDate.toStringAsFixed(2),
          e.balance.toStringAsFixed(2),
          '"${e.comment ?? ''}"',
        ].join(','),
      );
    }
    final csv = rows.join('\n');
    if (mounted) {
      Clipboard.setData(ClipboardData(text: csv));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported ${students.length} rows to clipboard.'),
        ),
      );
    }
  }
}
