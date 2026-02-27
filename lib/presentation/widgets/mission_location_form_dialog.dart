import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/mission_location_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';

/// Modal for Add / Edit mission location (name, description, isActive).
class MissionLocationFormDialog extends ConsumerStatefulWidget {
  const MissionLocationFormDialog({
    super.key,
    required this.isEdit,
    this.location,
    required this.onSaved,
  });

  final bool isEdit;
  final MissionLocation? location;
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
        builder: (context, ref, _) => MissionLocationFormDialog(
          isEdit: false,
          onSaved: onSaved,
        ),
      ),
    );
  }

  static Future<void> showEdit({
    required BuildContext context,
    required WidgetRef ref,
    required MissionLocation location,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) => MissionLocationFormDialog(
          isEdit: true,
          location: location,
          onSaved: onSaved,
        ),
      ),
    );
  }

  @override
  ConsumerState<MissionLocationFormDialog> createState() =>
      _MissionLocationFormDialogState();
}

class _MissionLocationFormDialogState extends ConsumerState<MissionLocationFormDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late bool _isActive;

  @override
  void initState() {
    super.initState();
    final loc = widget.location;
    _nameController = TextEditingController(text: loc?.name ?? '');
    _descriptionController = TextEditingController(text: loc?.description ?? '');
    _isActive = loc?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
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
                      'Location Name',
                      _nameController,
                      redColor,
                      colorScheme,
                      isDark,
                      hint: 'e.g. Nairobi, Kenya',
                    ),
                    const SizedBox(height: 16),
                    _buildField(
                      'Description',
                      _descriptionController,
                      redColor,
                      colorScheme,
                      isDark,
                      hint: 'Optional',
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),
                    _buildActiveSwitch(isDark),
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
                  widget.isEdit ? 'Edit Location' : 'Add New Location',
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
                      ? 'Update the location details below.'
                      : 'Fill in the details below to add a new mission location.',
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
          textCapitalization: TextCapitalization.words,
          style: TextStyle(
            color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
            fontSize: 14,
          ),
          autofocus: !widget.isEdit,
        ),
      ],
    );
  }

  Widget _buildActiveSwitch(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Active',
            style: TextStyle(
              color: isDark ? AppColors.textOnDark : AppColors.charisBlack,
              fontWeight: FontWeight.w600,
              fontSize: 14,
              fontFamily: 'Questrial',
            ),
          ),
        ),
        Switch(
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
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
            foregroundColor:
                isDark ? AppColors.textSecondaryOnDark : AppColors.charisDarkGray,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Text(widget.isEdit ? 'Save' : 'Add Location'),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location name is required')),
      );
      return;
    }
    final auth = ref.read(authStateProvider).valueOrNull;
    if (auth is! Authenticated) return;

    final description = _descriptionController.text.trim();
    final descriptionOrNull =
        description.isEmpty ? null : description;

    try {
      if (widget.isEdit && widget.location != null) {
        await ref.read(missionLocationRepositoryProvider).updateMissionLocation(
              widget.location!.id,
              name: name,
              description: descriptionOrNull,
              isActive: _isActive,
              userRole: auth.role,
              userId: auth.user.id,
              userDisplayName: auth.user.displayName,
              screen: 'Mission Locations',
            );
      } else {
        await ref.read(missionLocationRepositoryProvider).addMissionLocation(
              name,
              description: descriptionOrNull,
              isActive: _isActive,
              userRole: auth.role,
              userId: auth.user.id,
              userDisplayName: auth.user.displayName,
              screen: 'Mission Locations',
            );
      }
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.isEdit
                  ? 'Location updated successfully'
                  : 'Location added successfully',
            ),
          ),
        );
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
