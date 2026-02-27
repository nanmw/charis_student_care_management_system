import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/subject_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';

/// Styled modal for Add / Edit subject (white card, red primary button).
class SubjectFormDialog extends ConsumerStatefulWidget {
  const SubjectFormDialog({
    super.key,
    required this.isEdit,
    this.subject,
    this.initialClassId,
    required this.onSaved,
  });

  final bool isEdit;
  final Subject? subject;
  final int? initialClassId;
  final VoidCallback onSaved;

  static Future<void> showAdd({
    required BuildContext context,
    required WidgetRef ref,
    required int classId,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) => SubjectFormDialog(
          isEdit: false,
          initialClassId: classId,
          onSaved: onSaved,
        ),
      ),
    );
  }

  static Future<void> showEdit({
    required BuildContext context,
    required WidgetRef ref,
    required Subject subject,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) => SubjectFormDialog(
          isEdit: true,
          subject: subject,
          onSaved: onSaved,
        ),
      ),
    );
  }

  @override
  ConsumerState<SubjectFormDialog> createState() => _SubjectFormDialogState();
}

class _SubjectFormDialogState extends ConsumerState<SubjectFormDialog> {
  late final TextEditingController _nameController;
  int? _classId;

  @override
  void initState() {
    super.initState();
    final s = widget.subject;
    _nameController = TextEditingController(text: s?.name ?? '');
    _classId = s?.classId ?? widget.initialClassId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
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
                    _buildField('Subject Name', _nameController, redColor, colorScheme, isDark, hint: 'Enter subject name'),
                    const SizedBox(height: 16),
                    _buildClassDropdown(redColor, colorScheme, isDark),
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
                  widget.isEdit ? 'Edit Subject' : 'Add New Subject',
                  style: TextStyle(
                    color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    fontFamily: 'Questrial',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.isEdit
                      ? 'Update the subject details below.'
                      : 'Fill in the details below to add a new subject.',
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
              borderSide: const BorderSide(color: AppColors.charisMidGray),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: redColor, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            filled: true,
            fillColor: isDark ? AppColors.surfaceDark : AppColors.charisWhite,
          ),
          textCapitalization: TextCapitalization.words,
          style: TextStyle(color: isDark ? AppColors.textOnDark : AppColors.charisBlack, fontSize: 14),
          autofocus: !widget.isEdit,
        ),
      ],
    );
  }

  Widget _buildClassDropdown(Color redColor, ColorScheme colorScheme, bool isDark) {
    final classesAsync = ref.watch(allClassesFutureProvider);
    return classesAsync.when(
      data: (classes) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Class',
              style: TextStyle(
                color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
                fontWeight: FontWeight.w600,
                fontSize: 14,
                fontFamily: 'Questrial',
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              initialValue: _classId,
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
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                filled: true,
                fillColor: isDark ? AppColors.surfaceDark : AppColors.charisWhite,
              ),
              hint: const Text('Select Class', style: TextStyle(fontSize: 14)),
              items: classes.map((c) => DropdownMenuItem<int>(value: c.id, child: Text(c.name))).toList(),
              onChanged: widget.isEdit ? null : (v) => setState(() => _classId = v),
              style: TextStyle(
                color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
                fontSize: 14,
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox(height: 56),
      error: (e, _) => Text('Error loading classes: $e'),
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
          child: Text(widget.isEdit ? 'Save' : 'Add Subject'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Subject name is required')),
      );
      return;
    }
    if (_classId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Class is required')),
      );
      return;
    }
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return;

    try {
      if (widget.isEdit && widget.subject != null) {
        await ref.read(subjectRepositoryProvider).updateSubject(
              widget.subject!.id,
              name: name,
              userRole: auth.role,
              userId: auth.user.id,
              userDisplayName: auth.user.displayName,
              screen: 'Subjects',
            );
      } else {
        await ref.read(subjectRepositoryProvider).addSubject(
              name,
              _classId!,
              userRole: auth.role,
              userId: auth.user.id,
              userDisplayName: auth.user.displayName,
              screen: 'Subjects',
            );
      }
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
