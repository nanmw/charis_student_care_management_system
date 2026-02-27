import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/mission_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/widgets/searchable_dropdown.dart';

/// Role options for mission sign-up.
const List<String> missionRoleOptions = [
  'Volunteer',
  'Translator',
  'Logistics Coordinator',
  'Mentor',
  'Participant',
];

/// Modal to sign up a student for a mission (select student + role).
class MissionSignupDialog extends ConsumerStatefulWidget {
  const MissionSignupDialog({
    super.key,
    required this.mission,
    required this.slotsAvailable,
    required this.onSaved,
  });

  final Mission mission;
  final int slotsAvailable;
  final VoidCallback onSaved;

  static Future<void> show({
    required BuildContext context,
    required WidgetRef ref,
    required Mission mission,
    required int slotsAvailable,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) => MissionSignupDialog(
          mission: mission,
          slotsAvailable: slotsAvailable,
          onSaved: onSaved,
        ),
      ),
    );
  }

  @override
  ConsumerState<MissionSignupDialog> createState() =>
      _MissionSignupDialogState();
}

class _MissionSignupDialogState extends ConsumerState<MissionSignupDialog> {
  Student? _selectedStudent;
  String? _selectedRole;
  late final TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    final defaultAmount = widget.mission.amount ?? 0.0;
    _amountController = TextEditingController(
      text: defaultAmount > 0 ? defaultAmount.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
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
    final studentsAsync =
        ref.watch(studentsEligibleForMissionsProvider(widget.mission.mode));

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
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
                    Text(
                      widget.mission.title,
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textOnDark
                            : AppColors.charisBlack,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                        fontFamily: 'Questrial',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.slotsAvailable} slots available',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.textSecondaryOnDark
                            : AppColors.charisMidGray,
                        fontSize: 14,
                        fontFamily: 'Questrial',
                      ),
                    ),
                    const SizedBox(height: 20),
                    studentsAsync.when(
                      data: (students) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SearchableDropdown<Student>(
                              label: 'Student',
                              items: students,
                              selectedValue: _selectedStudent,
                              hint: 'Select a student',
                              displayTextBuilder: (s) =>
                                  '${s.surname}, ${s.firstName}',
                              searchFilter: (s, q) {
                                final lower = q.toLowerCase();
                                return s.surname
                                        .toLowerCase()
                                        .contains(lower) ||
                                    s.firstName.toLowerCase().contains(lower);
                              },
                              onChanged: (v) =>
                                  setState(() => _selectedStudent = v),
                            ),
                            const SizedBox(height: 16),
                            _buildAmountField(redColor, colorScheme, isDark),
                            const SizedBox(height: 16),
                            _buildRoleDropdown(redColor, colorScheme, isDark),
                            const SizedBox(height: 24),
                            _buildActions(context, redColor, isDark),
                          ],
                        );
                      },
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (e, _) => Center(
                        child: Text(
                          'Error loading students: $e',
                          style: TextStyle(
                            color: colorScheme.error,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
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
                  'Sign up for mission',
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
                  'Select a student and their role.',
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

  Widget _buildAmountField(
    Color redColor,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Amount (R)',
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Amount student will pay for this trip',
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
        ),
      ],
    );
  }

  Widget _buildRoleDropdown(
    Color redColor,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Role',
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
            fontWeight: FontWeight.w600,
            fontSize: 14,
            fontFamily: 'Questrial',
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _selectedRole,
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
          hint: Text(
            'Select role',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
          ),
          items: missionRoleOptions
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (v) => setState(() => _selectedRole = v),
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
            fontSize: 14,
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
          child: const Text(
            'Sign up',
            style: TextStyle(fontFamily: 'Questrial'),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_selectedStudent == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a student')),
      );
      return;
    }
    final amountStr = _amountController.text.trim();
    final amount =
        amountStr.isEmpty ? 0.0 : (double.tryParse(amountStr) ?? 0.0);
    if (amount < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Amount must be 0 or more')),
      );
      return;
    }
    final role = _selectedRole?.trim() ?? missionRoleOptions.first;
    try {
      await ref.read(missionRepositoryProvider).addParticipation(
            missionId: widget.mission.id,
            studentId: _selectedStudent!.id,
            role: role.isEmpty ? missionRoleOptions.first : role,
            amount: amount,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Student signed up successfully')),
      );
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
