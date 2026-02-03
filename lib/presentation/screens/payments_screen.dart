import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/core/utils/currency_utils.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/data/repositories/payment_repository.dart';
import 'package:charis_student_care/data/repositories/payment_repository.dart' show PaymentData;
import 'package:charis_student_care/domain/use_cases/sort_students_alphabetically.dart';
import 'package:charis_student_care/presentation/providers/payment_providers.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';

/// Month column labels (Jan–Oct for display).
const List<String> _monthLabels = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct'
];

const List<String> _modeOptions = ['Full-time', 'Hybrid'];
const List<String?> _academicYearOptions = [null, 'Year 1', 'Year 2', 'Year 3'];

/// Individual editable payment cell widget to isolate rebuilds
class _PaymentCell extends StatefulWidget {
  const _PaymentCell({
    required this.controller,
    required this.colorScheme,
    required this.onChanged,
    this.width = 70,
  });

  final TextEditingController controller;
  final ColorScheme colorScheme;
  final void Function(double) onChanged;
  final double width;

  @override
  State<_PaymentCell> createState() => _PaymentCellState();
}

class _PaymentCellState extends State<_PaymentCell> {
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
                fontSize: 13),
            border: InputBorder.none,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            isDense: true,
          ),
          style: TextStyle(
              color: widget.colorScheme.onSurface,
              fontSize: 13),
          onChanged: (v) {
            final n = double.tryParse(v);
            if (n != null && n >= 0) {
              // Debounce updates to reduce rebuild frequency
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

/// Display-only cell for currency values (Total Paid, Balance)
class _PaymentDisplayCell extends StatelessWidget {
  const _PaymentDisplayCell({
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

/// One row's editable payment state (Jan–Oct + lump sum).
class _PaymentRowEdit {
  _PaymentRowEdit({
    this.jan = 0,
    this.feb = 0,
    this.mar = 0,
    this.apr = 0,
    this.may = 0,
    this.jun = 0,
    this.jul = 0,
    this.aug = 0,
    this.sep = 0,
    this.oct = 0,
    this.lumpSum = 0,
  });

  double jan;
  double feb;
  double mar;
  double apr;
  double may;
  double jun;
  double jul;
  double aug;
  double sep;
  double oct;
  double lumpSum;

  // Cached formatted currency strings
  String? _cachedTotalPaidFormatted;
  String? _cachedBalanceFormatted;
  double? _lastTotalPaid;
  double? _lastBalance;

  double get totalPaid =>
      jan + feb + mar + apr + may + jun + jul + aug + sep + oct + lumpSum;
  double get balance =>
      AppConstants.fullTuitionAmount - totalPaid;

  String get totalPaidFormatted {
    final current = totalPaid;
    if (_lastTotalPaid != current) {
      _lastTotalPaid = current;
      _cachedTotalPaidFormatted = CurrencyUtils.formatRand(current);
    }
    return _cachedTotalPaidFormatted ?? CurrencyUtils.formatRand(current);
  }

  String get balanceFormatted {
    final current = balance;
    if (_lastBalance != current) {
      _lastBalance = current;
      _cachedBalanceFormatted = CurrencyUtils.formatRand(current);
    }
    return _cachedBalanceFormatted ?? CurrencyUtils.formatRand(current);
  }

  void invalidateCache() {
    _cachedTotalPaidFormatted = null;
    _cachedBalanceFormatted = null;
    // Reset to force recalculation on next access
    _lastTotalPaid = null;
    _lastBalance = null;
  }
}

class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  String _selectedMode = 'Full-time';
  String? _academicYear;
  String _paymentYear = DateTime.now().year.toString();
  String _searchQuery = '';
  // Store edits per payment year to preserve them when switching years
  final Map<String, Map<int, _PaymentRowEdit>> _paymentEditsByYear = {};
  final Map<String, TextEditingController> _controllers = {};
  String _refillKey = '';
  String? _lastPaymentYear;
  
  // Debouncing for text input
  final Map<String, Timer> _debounceTimers = {};
  
  // Memoization for filtered/sorted lists
  List<Student>? _cachedFilteredStudents;
  String _lastFilterKey = '';
  
  // Cached payment map to avoid recreating on every refill
  Map<int, Payment>? _cachedPaymentMap;
  int? _cachedPaymentHash;
  
  // Pagination state
  int _pageSize = 15; // Default 15 rows per page
  int _currentPage = 0;

  // Helper to get current year's edits map (ensures it exists)
  Map<int, _PaymentRowEdit> get _currentYearEdits {
    return _paymentEditsByYear.putIfAbsent(_paymentYear, () => {});
  }

  @override
  void dispose() {
    // Cancel all debounce timers
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    
    // Dispose all controllers
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Debounced update method
  void _debouncedUpdate(String key, void Function() update, {Duration delay = const Duration(milliseconds: 300)}) {
    _debounceTimers[key]?.cancel();
    _debounceTimers[key] = Timer(delay, () {
      update();
      _debounceTimers.remove(key);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final studentsAsync = ref.watch(studentsStreamProvider('Active'));
    final paymentsAsync = ref.watch(paymentsForYearStreamProvider(_paymentYear));

    return RoleGuard(
      canShow: (role) => RolePermissions.canManageFinancials(role),
      placeholder: Center(
        child: Text(
          'You do not have permission to view or manage payments.',
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Student Payment Records',
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        fontSize: 24,
                        fontFamily: 'Questrial',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage Payments',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontFamily: 'Questrial',
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => _exportCsv(context),
                      icon: const Icon(Icons.download, size: 20),
                      label: const Text('Export'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.onSurfaceVariant,
                        side: BorderSide(color: colorScheme.outline),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save, size: 20,
                          color: AppColors.charisWhite),
                      label: const Text('Save',
                          style: TextStyle(
                              color: AppColors.charisWhite,
                              fontFamily: 'Questrial',
                              fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryActionRed,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildFiltersRow(colorScheme),
            const SizedBox(height: 24),
            Expanded(
              child: studentsAsync.when(
                data: (allStudents) {
                  // Memoize filtered/sorted list
                  final filterKey = '$_selectedMode|$_academicYear|$_searchQuery';
                  if (_cachedFilteredStudents == null || _lastFilterKey != filterKey) {
                    // Optimized: combine filters into single pass to reduce allocations
                    final searchQueryLower = _searchQuery.toLowerCase();
                    final filtered = allStudents.where((s) {
                      // Mode filter
                      if (s.mode != _selectedMode) return false;
                      // Academic year filter
                      if (_academicYear != null && s.year != _academicYear) return false;
                      // Search filter
                      if (searchQueryLower.isNotEmpty) {
                        if (!s.surname.toLowerCase().contains(searchQueryLower) &&
                            !s.firstName.toLowerCase().contains(searchQueryLower) &&
                            !(s.email?.toLowerCase().contains(searchQueryLower) ?? false)) {
                          return false;
                        }
                      }
                      return true;
                    }).toList();
                    _cachedFilteredStudents = sortStudentsAlphabetically(filtered);
                    _lastFilterKey = filterKey;
                  }
                  final allFilteredStudents = _cachedFilteredStudents!;
                  
                  // Apply pagination
                  final total = allFilteredStudents.length;
                  final totalPages = total == 0 ? 1 : ((total - 1) / _pageSize).floor() + 1;
                  
                  // Handle edge case: if current page exceeds available pages, reset to last valid page
                  if (_currentPage >= totalPages && totalPages > 0) {
                    _currentPage = totalPages - 1;
                  }
                  
                  final start = _currentPage * _pageSize;
                  final pageStudents = total == 0
                      ? <Student>[]
                      : allFilteredStudents.sublist(start, (start + _pageSize).clamp(0, total));
                  
                  // Wait for payments to load before initializing edits
                  return paymentsAsync.when(
                    data: (paymentRows) {
                      // Initialize edits for ALL filtered students, but controllers only for current page
                      _refillEditsIfNeeded(allFilteredStudents, paymentRows, pageStudents: pageStudents);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Student Payment Details',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w700,
                              fontSize: 18,
                              fontFamily: 'Questrial',
                            ),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: allFilteredStudents.isEmpty
                                ? Center(
                                    child: Text(
                                      'No students match the selected filters.',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 14,
                                        fontFamily: 'Questrial',
                                      ),
                                    ),
                                  )
                                : _buildTable(
                                    context, colorScheme, pageStudents),
                          ),
                          if (allFilteredStudents.isNotEmpty) _buildPagination(total),
                        ],
                      );
                    },
                    loading: () => Center(
                        child: CircularProgressIndicator(
                            color: colorScheme.onSurface)),
                    error: (err, _) => Center(
                      child: Text('Error loading payments: $err',
                          style: TextStyle(color: colorScheme.onSurface)),
                    ),
                  );
                },
                loading: () => Center(
                    child: CircularProgressIndicator(
                        color: colorScheme.onSurface)),
                error: (err, _) => Center(
                  child: Text('Error: $err',
                      style: TextStyle(color: colorScheme.onSurface)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _refillEditsIfNeeded(
      List<Student> students, List<Payment> paymentRows, {List<Student>? pageStudents}) {
    // Optimized hash calculation using Object.hashAll instead of string concatenation
    final paymentHash = paymentRows.isEmpty 
        ? 0 
        : Object.hashAll(paymentRows.map((p) => Object.hash(
            p.studentId, p.jan, p.feb, p.mar, p.apr, p.may, 
            p.jun, p.jul, p.aug, p.sep, p.oct, p.lumpSum)));
    
    // Cache payment map if hash hasn't changed
    Map<int, Payment> paymentMap;
    if (_cachedPaymentMap != null && _cachedPaymentHash == paymentHash) {
      paymentMap = _cachedPaymentMap!;
    } else {
      paymentMap = {for (final p in paymentRows) p.studentId: p};
      _cachedPaymentMap = paymentMap;
      _cachedPaymentHash = paymentHash;
    }
    
    // Simplified key generation - use payment count + year + hash
    final key = '${_paymentYear}_${students.length}_${paymentRows.length}_$paymentHash';
    final shouldSkipEditRefill = key == _refillKey && _lastPaymentYear == _paymentYear;
    
    if (!shouldSkipEditRefill) {
      _refillKey = key;
      _lastPaymentYear = _paymentYear;
    }
    
    // Get current year's edits map
    final edits = _currentYearEdits;
    
    // Determine which students need controllers (paginated students, or all if not paginated)
    final studentsForControllers = pageStudents ?? students;
    final controllerStudentIds = studentsForControllers.map((s) => s.id).toSet();
    
    // Clean up controllers for students no longer visible on current page
    for (final k in _controllers.keys.toList()) {
      final studentId = int.tryParse(k.split('_').first);
      if (studentId == null || !controllerStudentIds.contains(studentId)) {
        _controllers[k]?.dispose();
        _controllers.remove(k);
      }
    }
    
    // Track if any changes were made to determine if setState is needed
    bool hasChanges = false;
    
    // Only initialize/update edits if not skipping
    if (!shouldSkipEditRefill) {
      // Initialize or update edits for ALL filtered students (not just paginated)
      // This ensures all payment data is loaded into memory for persistence
      for (final s in students) {
        final p = paymentMap[s.id];
        // Only create new edit if it doesn't exist (preserves unsaved changes)
        if (!edits.containsKey(s.id)) {
          edits[s.id] = _PaymentRowEdit(
            jan: p?.jan ?? 0,
            feb: p?.feb ?? 0,
            mar: p?.mar ?? 0,
            apr: p?.apr ?? 0,
            may: p?.may ?? 0,
            jun: p?.jun ?? 0,
            jul: p?.jul ?? 0,
            aug: p?.aug ?? 0,
            sep: p?.sep ?? 0,
            oct: p?.oct ?? 0,
            lumpSum: p?.lumpSum ?? 0,
          );
          hasChanges = true;
        } else {
          // Update from database only if no unsaved changes exist
          final existing = edits[s.id]!;
          final dbJan = p?.jan ?? 0;
          final dbFeb = p?.feb ?? 0;
          final dbMar = p?.mar ?? 0;
          final dbApr = p?.apr ?? 0;
          final dbMay = p?.may ?? 0;
          final dbJun = p?.jun ?? 0;
          final dbJul = p?.jul ?? 0;
          final dbAug = p?.aug ?? 0;
          final dbSep = p?.sep ?? 0;
          final dbOct = p?.oct ?? 0;
          final dbLumpSum = p?.lumpSum ?? 0;
          
          // Check if current edit matches database (no unsaved changes)
          final hasUnsavedChanges = existing.jan != dbJan ||
              existing.feb != dbFeb ||
              existing.mar != dbMar ||
              existing.apr != dbApr ||
              existing.may != dbMay ||
              existing.jun != dbJun ||
              existing.jul != dbJul ||
              existing.aug != dbAug ||
              existing.sep != dbSep ||
              existing.oct != dbOct ||
              existing.lumpSum != dbLumpSum;
          
          if (!hasUnsavedChanges && p != null) {
            // No unsaved changes, update from database
            final updatedEdit = _PaymentRowEdit(
              jan: p.jan,
              feb: p.feb,
              mar: p.mar,
              apr: p.apr,
              may: p.may,
              jun: p.jun,
              jul: p.jul,
              aug: p.aug,
              sep: p.sep,
              oct: p.oct,
              lumpSum: p.lumpSum,
            );
            edits[s.id] = updatedEdit;
            // Invalidate cache to force recalculation
            updatedEdit.invalidateCache();
            hasChanges = true;
          }
        }
      }
    }
    
    // ALWAYS initialize controllers for current page students, even if skipping edit refill
    // This ensures controllers exist when _buildTable accesses them
    for (final s in studentsForControllers) {
      final edit = edits[s.id] ?? _PaymentRowEdit();
      
      // Initialize controllers if needed and update text only if changed
      for (var i = 0; i < _monthLabels.length; i++) {
        final field = _monthLabels[i].toLowerCase();
        final ctrlKey = '${s.id}_$field';
        final controller = _controllers[ctrlKey] ??= TextEditingController();
        
        final val = [
          edit.jan, edit.feb, edit.mar, edit.apr, edit.may,
          edit.jun, edit.jul, edit.aug, edit.sep, edit.oct,
        ][i];
        final newText = val == 0 ? '' : val.toStringAsFixed(0);
        
        // Only update if text actually changed to avoid cursor jumping
        if (controller.text != newText) {
          controller.text = newText;
          hasChanges = true;
        }
      }
      
      final lumpKey = '${s.id}_lumpSum';
      final lumpController = _controllers[lumpKey] ??= TextEditingController();
      final lumpText = edit.lumpSum == 0 ? '' : edit.lumpSum.toStringAsFixed(0);
      if (lumpController.text != lumpText) {
        lumpController.text = lumpText;
        hasChanges = true;
      }
    }
    
    // Only call setState if changes were actually made
    if (hasChanges && mounted) {
      setState(() {});
    }
  }

  Widget _buildFiltersRow(ColorScheme colorScheme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text('Student Mode:',
            style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial')),
        const SizedBox(width: 8),
        _buildModeToggle(colorScheme),
        const SizedBox(width: 24),
        Text('Academic Year:',
            style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial')),
        const SizedBox(width: 8),
        _buildAcademicYearDropdown(colorScheme),
        const SizedBox(width: 24),
        Text('Payment Year:',
            style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
                fontFamily: 'Questrial')),
        const SizedBox(width: 8),
        _buildPaymentYearField(colorScheme),
        const SizedBox(width: 24),
        Expanded(
          child: TextField(
            onChanged: (v) {
              // Debounce search query updates
              _debouncedUpdate('search', () {
                if (mounted) {
                  setState(() {
                    _searchQuery = v;
                    _currentPage = 0; // Reset to first page
                  });
                }
              });
            },
            decoration: InputDecoration(
              hintText: 'Search students...',
              hintStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant, fontSize: 14),
              prefixIcon: Icon(Icons.search,
                  color: colorScheme.onSurfaceVariant, size: 22),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            style: TextStyle(color: colorScheme.onSurface, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildModeToggle(ColorScheme colorScheme) {
    return ToggleButtons(
      constraints: const BoxConstraints(minWidth: 90, minHeight: 44),
      borderRadius: BorderRadius.circular(8),
      fillColor: AppColors.primaryActionRed,
      selectedColor: AppColors.charisWhite,
      color: colorScheme.onSurface,
      isSelected: _modeOptions.map((m) => m == _selectedMode).toList(),
      onPressed: (index) {
        setState(() {
          _selectedMode = _modeOptions[index];
          _cachedFilteredStudents = null; // Invalidate cache
          _currentPage = 0; // Reset to first page
        });
      },
      children: _modeOptions
          .map((l) =>
              Text(l, style: const TextStyle(fontFamily: 'Questrial', fontSize: 14)))
          .toList(),
    );
  }

  Widget _buildAcademicYearDropdown(ColorScheme colorScheme) {
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
          value: _academicYear,
          hint: Text('All',
              style: TextStyle(
                  color: colorScheme.onSurfaceVariant, fontSize: 14)),
          isExpanded: true,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(8),
          items: _academicYearOptions
              .map((y) => DropdownMenuItem<String?>(
                    value: y,
                    child: Text(y ?? 'All',
                        style: TextStyle(
                            color: colorScheme.onSurface, fontSize: 14)),
                  ))
              .toList(),
          onChanged: (v) {
            setState(() {
              _academicYear = v;
              _cachedFilteredStudents = null; // Invalidate cache
              _currentPage = 0; // Reset to first page
            });
          },
        ),
      ),
    );
  }

  Widget _buildPaymentYearField(ColorScheme colorScheme) {
    return SizedBox(
      width: 90,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colorScheme.outline),
        ),
        child: DropdownButton<String>(
          value: _paymentYear,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(8),
          items: ['2024', '2025', '2026', '2027']
              .map((y) => DropdownMenuItem<String>(
                    value: y,
                    child: Text(y,
                        style: TextStyle(
                            color: colorScheme.onSurface, fontSize: 14)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() {
                _paymentYear = v;
                _cachedFilteredStudents = null; // Invalidate cache
                _currentPage = 0; // Reset to first page
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildTable(
      BuildContext context, ColorScheme colorScheme, List<Student> students) {
    final edits = _currentYearEdits;
    
    return LayoutBuilder(
      builder: (context, constraints) {
        return RepaintBoundary(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Table(
                columnWidths: {
                  0: const FixedColumnWidth(160),
                  ...Map.fromEntries(List.generate(
                      _monthLabels.length,
                      (i) => MapEntry(
                          i + 1, const FixedColumnWidth(72)))),
                  _monthLabels.length + 1: const FixedColumnWidth(80),
                  _monthLabels.length + 2: const FixedColumnWidth(100),
                  _monthLabels.length + 3: const FixedColumnWidth(110),
                },
                border: TableBorder.all(color: colorScheme.outlineVariant),
                children: [
                  // Table header row - using const where possible
                  TableRow(
                    decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest),
                    children: [
                      _tableHeader(context, 'Student Name'),
                      ..._monthLabels.map((l) => _tableHeader(context, l)),
                      _tableHeader(context, 'Lump Sum'),
                      _tableHeader(context, 'Total Paid'),
                      _tableHeader(context, 'Balance (Rand)'),
                    ],
                  ),
                  ...students.asMap().entries.map((e) {
                    final index = e.key;
                    final student = e.value;
                    final edit = edits[student.id] ?? _PaymentRowEdit();
                    Color rowColor = index.isEven
                        ? colorScheme.surface
                        : colorScheme.surfaceContainerLow
                            .withValues(alpha: 0.5);
                    return TableRow(
                      decoration: BoxDecoration(color: rowColor),
                      children: [
                        _cell(
                            context,
                            colorScheme,
                            RepaintBoundary(
                              child: Text(
                                  '${student.surname} ${student.firstName}',
                                  style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontSize: 14,
                                      fontFamily: 'Questrial')),
                            )),
                        ..._monthLabels.asMap().entries.map((entry) {
                          final i = entry.key;
                          final field = entry.value.toLowerCase();
                          final ctrlKey = '${student.id}_$field';
                          // Controllers are initialized in _refillEditsIfNeeded
                          // Use null-safe access with fallback to prevent crashes (shouldn't happen, but safety measure)
                          final controller = _controllers[ctrlKey] ??= TextEditingController();
                          
                          return _cell(
                              context,
                              colorScheme,
                              _PaymentCell(
                                controller: controller,
                                colorScheme: colorScheme,
                                onChanged: (n) {
                                  if (mounted) {
                                    setState(() {
                                      final e = edits[student.id] ??= 
                                          _PaymentRowEdit();
                                      e.invalidateCache();
                                      switch (i) {
                                        case 0: e.jan = n; break;
                                        case 1: e.feb = n; break;
                                        case 2: e.mar = n; break;
                                        case 3: e.apr = n; break;
                                        case 4: e.may = n; break;
                                        case 5: e.jun = n; break;
                                        case 6: e.jul = n; break;
                                        case 7: e.aug = n; break;
                                        case 8: e.sep = n; break;
                                        case 9: e.oct = n; break;
                                      }
                                    });
                                  }
                                },
                              ));
                        }),
                        _cell(
                            context,
                            colorScheme,
                            _PaymentCell(
                              controller: _controllers['${student.id}_lumpSum'] ??= TextEditingController(),
                              colorScheme: colorScheme,
                              width: 76,
                              onChanged: (n) {
                                if (mounted) {
                                  setState(() {
                                    final e = edits[student.id] ??= 
                                        _PaymentRowEdit();
                                    e.invalidateCache();
                                    e.lumpSum = n;
                                  });
                                }
                              },
                            )),
                        _cell(
                            context,
                            colorScheme,
                            _PaymentDisplayCell(
                              text: edit.totalPaidFormatted,
                              colorScheme: colorScheme,
                            )),
                        _cell(
                            context,
                            colorScheme,
                            _PaymentDisplayCell(
                              text: edit.balanceFormatted,
                              colorScheme: colorScheme,
                              textColor: edit.balance > 0
                                  ? colorScheme.error
                                  : colorScheme.onSurface,
                            )),
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

  Widget _cell(
      BuildContext context, ColorScheme colorScheme, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: child,
    );
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
            style: TextStyle(
              color: colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
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
                  style: const TextStyle(
                    color: AppColors.charisWhite,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
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

  Future<void> _save() async {
    try {
      final repo = ref.read(paymentRepositoryProvider);
      final edits = _currentYearEdits; // Use the helper to get current year's edits
      
      if (edits.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No payments to save.')));
        }
        return;
      }
      
      // Get current payment rows from database for comparison
      final currentPaymentRows = await repo.watchPaymentsForYear(_paymentYear).first;
      final paymentMap = {for (final p in currentPaymentRows) p.studentId: p};
      
      // Convert only changed edits to PaymentData map for batch operation
      final paymentDataMap = <int, PaymentData>{};
      
      for (final entry in edits.entries) {
        final studentId = entry.key;
        final edit = entry.value;
        final dbPayment = paymentMap[studentId];
        
        // Compare edit with database value to detect changes
        final dbJan = dbPayment?.jan ?? 0;
        final dbFeb = dbPayment?.feb ?? 0;
        final dbMar = dbPayment?.mar ?? 0;
        final dbApr = dbPayment?.apr ?? 0;
        final dbMay = dbPayment?.may ?? 0;
        final dbJun = dbPayment?.jun ?? 0;
        final dbJul = dbPayment?.jul ?? 0;
        final dbAug = dbPayment?.aug ?? 0;
        final dbSep = dbPayment?.sep ?? 0;
        final dbOct = dbPayment?.oct ?? 0;
        final dbLumpSum = dbPayment?.lumpSum ?? 0;
        
        // Check if any value has changed
        final hasChanges = edit.jan != dbJan ||
            edit.feb != dbFeb ||
            edit.mar != dbMar ||
            edit.apr != dbApr ||
            edit.may != dbMay ||
            edit.jun != dbJun ||
            edit.jul != dbJul ||
            edit.aug != dbAug ||
            edit.sep != dbSep ||
            edit.oct != dbOct ||
            edit.lumpSum != dbLumpSum;
        
        // Only include records that have actually changed
        if (hasChanges) {
          paymentDataMap[studentId] = PaymentData(
            jan: edit.jan,
            feb: edit.feb,
            mar: edit.mar,
            apr: edit.apr,
            may: edit.may,
            jun: edit.jun,
            jul: edit.jul,
            aug: edit.aug,
            sep: edit.sep,
            oct: edit.oct,
            nov: 0, // Not used in UI but required by schema
            dec: 0, // Not used in UI but required by schema
            lumpSum: edit.lumpSum,
          );
        }
      }
      
      if (paymentDataMap.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('No changes to save.')));
        }
        return;
      }
      
      // Use batch upsert for much better performance
      final savedCount = await repo.batchUpsertPayments(
        year: _paymentYear,
        payments: paymentDataMap,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Successfully saved $savedCount payment record(s).')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error saving payments: $e')));
      }
    }
  }

  void _exportCsv(BuildContext context) {
    final rows = <String>[];
    final header = [
      'Student Name',
      ..._monthLabels,
      'Lump Sum',
      'Total Paid',
      'Balance (Rand)',
    ];
    rows.add(header.join(','));
    final edits = _currentYearEdits; // Use current year's edits
    
    // Optimized: use cached filtered students instead of re-reading from provider
    final students = _cachedFilteredStudents ?? [];
    final studentMap = {for (final s in students) s.id: s};
    
    for (final entry in edits.entries) {
      final studentId = entry.key;
      final edit = entry.value;
      final student = studentMap[studentId];
      final name = student == null
          ? 'Student $studentId'
          : '${student.surname} ${student.firstName}';
      rows.add([
        '"$name"',
        edit.jan.toStringAsFixed(0),
        edit.feb.toStringAsFixed(0),
        edit.mar.toStringAsFixed(0),
        edit.apr.toStringAsFixed(0),
        edit.may.toStringAsFixed(0),
        edit.jun.toStringAsFixed(0),
        edit.jul.toStringAsFixed(0),
        edit.aug.toStringAsFixed(0),
        edit.sep.toStringAsFixed(0),
        edit.oct.toStringAsFixed(0),
        edit.lumpSum.toStringAsFixed(0),
        edit.totalPaid.toStringAsFixed(2),
        edit.balance.toStringAsFixed(2),
      ].join(','));
    }
    final csv = rows.join('\n');
    if (mounted) {
      Clipboard.setData(ClipboardData(text: csv));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Exported ${edits.length} rows to clipboard.')),
      );
    }
  }
}
