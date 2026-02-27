import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/app_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/mission_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';

/// Modal for Create / Edit mission (title, location, dates, slots, description, active, year).
class MissionFormDialog extends ConsumerStatefulWidget {
  const MissionFormDialog({
    super.key,
    required this.isEdit,
    this.mission,
    required this.onSaved,
  });

  final bool isEdit;
  final Mission? mission;
  final VoidCallback onSaved;

  static Future<void> showAdd({
    required BuildContext context,
    required WidgetRef ref,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) => MissionFormDialog(
          isEdit: false,
          onSaved: onSaved,
        ),
      ),
    );
  }

  static Future<void> showEdit({
    required BuildContext context,
    required WidgetRef ref,
    required Mission mission,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) => MissionFormDialog(
          isEdit: true,
          mission: mission,
          onSaved: onSaved,
        ),
      ),
    );
  }

  @override
  ConsumerState<MissionFormDialog> createState() => _MissionFormDialogState();
}

class _MissionFormDialogState extends ConsumerState<MissionFormDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _locationController;
  late final TextEditingController _slotsController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _amountController;
  DateTime? _startDate;
  DateTime? _endDate;
  String? _year;
  String _mode;
  bool _isActive = true;

  _MissionFormDialogState() : _mode = AppConstants.missionModeOptions.first;

  @override
  void initState() {
    super.initState();
    final m = widget.mission;
    _titleController = TextEditingController(text: m?.title ?? '');
    _locationController = TextEditingController(text: m?.location ?? '');
    _slotsController =
        TextEditingController(text: m != null ? m.slotsTotal.toString() : '');
    _descriptionController = TextEditingController(text: m?.description ?? '');
    _amountController = TextEditingController(
      text: m?.amount != null ? m!.amount!.toStringAsFixed(0) : '',
    );
    _startDate = m?.startDate ?? DateTime.now();
    _endDate = m?.endDate ?? DateTime.now().add(const Duration(days: 7));
    _year = m?.year ?? AppConstants.missionYearFilterOptions.first;
    _mode = m?.mode ?? AppConstants.missionModeOptions.first;
    _isActive = m?.isActive ?? true;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _slotsController.dispose();
    _descriptionController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor =
        isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDarkElevated : AppColors.charisWhite,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.2),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, isDark),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildField(
                      'Title',
                      _titleController,
                      redColor,
                      colorScheme,
                      isDark,
                      hint: 'e.g. Project Hope Africa',
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      'Location',
                      _locationController,
                      redColor,
                      colorScheme,
                      isDark,
                      hint: 'e.g. Nairobi, Kenya or Online',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _buildDateField(
                            'Start date',
                            _startDate!,
                            (d) => setState(() {
                              _startDate = d;
                              if (_endDate != null && _endDate!.isBefore(d)) {
                                _endDate = d;
                              }
                            }),
                            redColor,
                            colorScheme,
                            isDark,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildDateField(
                            'End date',
                            _endDate!,
                            (d) => setState(() => _endDate = d),
                            redColor,
                            colorScheme,
                            isDark,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      'Slots total',
                      _slotsController,
                      redColor,
                      colorScheme,
                      isDark,
                      hint: 'Number of participants',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      'Description (optional)',
                      _descriptionController,
                      redColor,
                      colorScheme,
                      isDark,
                      hint: 'Brief description',
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      'Default amount (R)',
                      _amountController,
                      redColor,
                      colorScheme,
                      isDark,
                      hint: 'Optional default trip cost',
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    _buildModeDropdown(redColor, colorScheme, isDark),
                    const SizedBox(height: 16),
                    _buildYearDropdown(redColor, colorScheme, isDark),
                    const SizedBox(height: 16),
                    _buildActiveCheckbox(isDark),
                    const SizedBox(height: 24),
                    _buildActions(context, redColor, isDark),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.isEdit ? 'Edit Mission' : 'Create Mission',
                  style: TextStyle(
                    color:
                        isDark ? AppColors.textOnDark : AppColors.charisBlack,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    fontFamily: 'Questrial',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.isEdit
                      ? 'Update the mission details below.'
                      : 'Fill in the details below to create a new mission.',
                  style: TextStyle(
                    color: isDark
                        ? AppColors.textSecondaryOnDark
                        : AppColors.charisMidGray,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close,
              color: isDark ? AppColors.textOnDark : AppColors.charisDarkGray,
            ),
            style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller,
    Color redColor,
    ColorScheme colorScheme,
    bool isDark, {
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint ?? label,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.charisMidGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: redColor, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            filled: true,
            fillColor: isDark ? AppColors.surfaceDark : AppColors.charisWhite,
          ),
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
            fontSize: 14,
          ),
          autofocus: !widget.isEdit,
        ),
      ],
    );
  }

  Widget _buildDateField(
    String label,
    DateTime value,
    ValueChanged<DateTime> onDate,
    Color redColor,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 6),
        InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(2020),
              lastDate: DateTime(2030),
            );
            if (picked != null) onDate(picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.charisMidGray),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              filled: true,
              fillColor: isDark ? AppColors.surfaceDark : AppColors.charisWhite,
            ),
            child: Text(
              value.toString().substring(0, 10),
              style: TextStyle(
                color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModeDropdown(
    Color redColor,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Mode (required)',
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _mode,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.charisMidGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: redColor, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            filled: true,
            fillColor: isDark ? AppColors.surfaceDark : AppColors.charisWhite,
          ),
          items: AppConstants.missionModeOptions
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (v) => setState(() => _mode = v ?? _mode),
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildYearDropdown(
    Color redColor,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Year',
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _year,
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.charisMidGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: redColor, width: 2),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            filled: true,
            fillColor: isDark ? AppColors.surfaceDark : AppColors.charisWhite,
          ),
          items: AppConstants.missionYearFilterOptions
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (v) => setState(() => _year = v),
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildActiveCheckbox(bool isDark) {
    return Row(
      children: [
        Checkbox(
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v ?? true),
          activeColor: AppColors.charisRedPrimary,
        ),
        Text(
          'Active',
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
      ],
    );
  }

  Widget _buildActions(BuildContext context, Color redColor, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(
              color: isDark ? AppColors.textOnDark : AppColors.charisDarkGray,
              fontFamily: 'Questrial',
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton(
          onPressed: _save,
          style: FilledButton.styleFrom(
            backgroundColor: redColor,
            foregroundColor: AppColors.charisWhite,
          ),
          child: Text(
            widget.isEdit ? 'Save' : 'Create',
            style: const TextStyle(fontFamily: 'Questrial'),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    final location = _locationController.text.trim();
    final slotsStr = _slotsController.text.trim();
    final description = _descriptionController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title is required')),
      );
      return;
    }
    if (location.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location is required')),
      );
      return;
    }
    final slots = int.tryParse(slotsStr);
    if (slots == null || slots < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Slots total must be at least 1')),
      );
      return;
    }
    if (_startDate == null || _endDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start and end dates are required')),
      );
      return;
    }
    if (_endDate!.isBefore(_startDate!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('End date must be on or after start date'),
        ),
      );
      return;
    }
    if (_year == null || _year!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Year is required')),
      );
      return;
    }
    if (_mode.isEmpty || !AppConstants.missionModeOptions.contains(_mode)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mode is required')),
      );
      return;
    }
    final amountStr = _amountController.text.trim();
    final amount = amountStr.isEmpty ? null : double.tryParse(amountStr);
    if (amountStr.isNotEmpty && (amount == null || amount < 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Default amount must be a non-negative number'),
        ),
      );
      return;
    }
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return;
    try {
      final repo = ref.read(missionRepositoryProvider);
      if (widget.isEdit && widget.mission != null) {
        await repo.updateMission(
          widget.mission!.id,
          title: title,
          location: location,
          startDate: _startDate!,
          endDate: _endDate!,
          slotsTotal: slots,
          description: description.isEmpty ? null : description,
          isActive: _isActive,
          year: _year!,
          mode: _mode,
          amount: amount,
          userRole: auth.role,
          userId: auth.user.id,
          userDisplayName: auth.user.displayName,
          screen: 'Missions',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mission updated')),
        );
      } else {
        await repo.addMission(
          title: title,
          location: location,
          startDate: _startDate!,
          endDate: _endDate!,
          slotsTotal: slots,
          description: description.isEmpty ? null : description,
          isActive: _isActive,
          year: _year!,
          mode: _mode,
          amount: amount,
          userRole: auth.role,
          userId: auth.user.id,
          userDisplayName: auth.user.displayName,
          screen: 'Missions',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mission created')),
        );
      }
      if (!mounted) return;
      widget.onSaved();
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }
}
