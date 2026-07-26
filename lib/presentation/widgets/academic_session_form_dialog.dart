import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/repositories/academic_session_repository.dart';
import 'package:charis_student_care/presentation/providers/academic_session_providers.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';

/// Add / Edit academic session (Admin only). Session = one year Feb–Oct; code e.g. "2026".
class AcademicSessionFormDialog extends ConsumerStatefulWidget {
  const AcademicSessionFormDialog({
    super.key,
    this.record,
    required this.onSaved,
  });

  final AcademicSessionRecord? record;
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
        builder: (context, ref, _) => AcademicSessionFormDialog(
          onSaved: onSaved,
        ),
      ),
    );
  }

  static Future<void> showEdit({
    required BuildContext context,
    required WidgetRef ref,
    required AcademicSessionRecord record,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) => AcademicSessionFormDialog(
          record: record,
          onSaved: onSaved,
        ),
      ),
    );
  }

  @override
  ConsumerState<AcademicSessionFormDialog> createState() => _AcademicSessionFormDialogState();
}

class _AcademicSessionFormDialogState extends ConsumerState<AcademicSessionFormDialog> {
  late final TextEditingController _codeController;
  late final TextEditingController _displayNameController;
  DateTime? _startDate;
  DateTime? _endDate;
  bool _isActive = false;

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    final r = widget.record;
    if (r != null) {
      _codeController = TextEditingController(text: r.code);
      _displayNameController = TextEditingController(text: r.displayName ?? '');
      _startDate = r.startDate;
      _endDate = r.endDate;
      _isActive = r.isActive;
    } else {
      final suggested = AcademicSessionRepository.suggestedSessionCode();
      _codeController = TextEditingController(text: suggested ?? '');
      _displayNameController = TextEditingController();
      final code = suggested ?? DateTime.now().year.toString();
      _startDate = AcademicSessionRepository.suggestedStartDate(code);
      _endDate = AcademicSessionRepository.suggestedEndDate(code);
      _isActive = false;
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final initial = isStart ? _startDate : _endDate;
    final suggested = isStart
        ? AcademicSessionRepository.suggestedStartDate(_codeController.text.trim())
        : AcademicSessionRepository.suggestedEndDate(_codeController.text.trim());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? suggested ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
    }
  }

  String _formatDate(DateTime? d) {
    if (d == null) return 'Select date';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor = isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
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
                      'Code (e.g. year: 2026)',
                      _codeController,
                      redColor,
                      colorScheme,
                      isDark,
                      hint: AcademicSessionRepository.suggestedSessionCode() ?? '2026',
                    ),
                    const SizedBox(height: 16),
                    _buildDateRow(context, redColor, colorScheme, isDark),
                    const SizedBox(height: 16),
                    _buildCheckbox(isDark),
                    const SizedBox(height: 16),
                    _buildField(
                      'Display name (optional)',
                      _displayNameController,
                      redColor,
                      colorScheme,
                      isDark,
                      hint: 'e.g. Session 2026',
                    ),
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
                  _isEdit ? 'Edit Academic Session' : 'Add Academic Session',
                  style: TextStyle(
                    color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    fontFamily: 'Questrial',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Session = one calendar year Feb–Oct. Set code, dates, and whether it is the current session.',
                  style: TextStyle(
                    color: isDark ? AppColors.textSecondaryOnDark : AppColors.charisMidGray,
                    fontSize: 14,
                    fontFamily: 'Questrial',
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close, color: isDark ? AppColors.textOnDark : AppColors.charisDarkGray),
            style: IconButton.styleFrom(padding: const EdgeInsets.all(4)),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, Color redColor, ColorScheme colorScheme, bool isDark, {String? hint}) {
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
          decoration: InputDecoration(
            hintText: hint ?? label,
            hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: redColor, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            filled: true,
            fillColor: isDark ? AppColors.surfaceDark : AppColors.charisWhite,
          ),
          style: TextStyle(color: isDark ? AppColors.textOnDark : AppColors.charisBlack, fontSize: 14),
          onChanged: (_) {
            if (!_isEdit) {
              final code = _codeController.text.trim();
              if (code.isNotEmpty) {
                final start = AcademicSessionRepository.suggestedStartDate(code);
                final end = AcademicSessionRepository.suggestedEndDate(code);
                if (start != null && _startDate == null) setState(() => _startDate = start);
                if (end != null && _endDate == null) setState(() => _endDate = end);
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildDateRow(BuildContext context, Color redColor, ColorScheme colorScheme, bool isDark) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Start date',
                style: TextStyle(
                  color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: () => _pickDate(context, true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppColors.textOnDark : AppColors.charisBlack,
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Text(_formatDate(_startDate)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'End date',
                style: TextStyle(
                  color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'Questrial',
                ),
              ),
              const SizedBox(height: 6),
              OutlinedButton(
                onPressed: () => _pickDate(context, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppColors.textOnDark : AppColors.charisBlack,
                  side: BorderSide(color: colorScheme.outlineVariant),
                ),
                child: Text(_formatDate(_endDate)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCheckbox(bool isDark) {
    return Row(
      children: [
        Checkbox(
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v ?? false),
          activeColor: isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary,
        ),
        Expanded(
          child: Text(
            'Set as current / active session',
            style: TextStyle(
              color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
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
          style: TextButton.styleFrom(
            foregroundColor: isDark ? AppColors.textSecondaryOnDark : AppColors.charisDarkGray,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 12),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: redColor,
            foregroundColor: AppColors.charisWhite,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          child: Text(_isEdit ? 'Save' : 'Add Session'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session code is required (e.g. 2026)')),
      );
      return;
    }
    final repo = ref.read(academicSessionRepositoryProvider);
    final auth = ref.read(authStateProvider).valueOrNull;
    final userRole = auth is Authenticated
        ? auth.role
        : UserRole.facilitator;
    final deviceId = await ref.read(deviceIdProvider.future);
    final userId = auth is Authenticated ? auth.user.id : null;
    final userDisplayName =
        auth is Authenticated ? auth.user.displayName : null;
    try {
      if (_isEdit && widget.record != null) {
        await repo.updateSession(
          widget.record!.id,
          userRole: userRole,
          code: code,
          startDate: _startDate,
          endDate: _endDate,
          isActive: _isActive,
          displayName: _displayNameController.text.trim().isEmpty ? null : _displayNameController.text.trim(),
          userId: userId,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: 'Settings',
        );
      } else {
        await repo.insertSession(
          code: code,
          userRole: userRole,
          startDate: _startDate,
          endDate: _endDate,
          isActive: _isActive,
          displayName: _displayNameController.text.trim().isEmpty ? null : _displayNameController.text.trim(),
          userId: userId,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: 'Settings',
        );
      }
      if (_isActive) {
        await repo.setCurrentSession(
          code,
          userRole: userRole,
          userId: userId,
          deviceId: deviceId,
          userDisplayName: userDisplayName,
          screen: 'Settings',
        );
      }
      ref.invalidate(currentAcademicSessionProvider);
      ref.invalidate(academicSessionOptionsProvider);
      ref.invalidate(allAcademicSessionsStreamProvider);
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }
}
