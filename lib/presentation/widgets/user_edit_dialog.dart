import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/repository_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';

/// Dialog to edit an existing user (display name, role, active, optional new password).
class UserEditDialog extends ConsumerStatefulWidget {
  const UserEditDialog({super.key, required this.user, required this.onSaved});

  final User user;
  final VoidCallback onSaved;

  static Future<void> show({
    required BuildContext context,
    required WidgetRef ref,
    required User user,
    required VoidCallback onSaved,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) => UserEditDialog(user: user, onSaved: onSaved),
      ),
    );
  }

  @override
  ConsumerState<UserEditDialog> createState() => _UserEditDialogState();
}

const List<String> _modeOptions = ['Full-time', 'Hybrid'];

class _UserEditDialogState extends ConsumerState<UserEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _displayNameController;
  late UserRole _role;
  late bool _isActive;
  final _newPasswordController = TextEditingController();
  int? _selectedClassId;
  String? _selectedMode;
  bool _scopeInitialized = false;

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(text: widget.user.displayName ?? '');
    _role = UserRole.fromString(widget.user.role);
    _isActive = widget.user.isActive;
    if (widget.user.allowedClassId != null) {
      _selectedClassId = widget.user.allowedClassId;
      _selectedMode = widget.user.allowedMode?.trim().isNotEmpty == true
          ? widget.user.allowedMode
          : 'Full-time';
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      await ref.read(userRepositoryProvider).updateUser(
            id: widget.user.id,
            displayName: _displayNameController.text.trim().isEmpty ? null : _displayNameController.text.trim(),
            role: _role,
            isActive: _isActive,
            newPlainPassword: _newPasswordController.text.isEmpty ? null : _newPasswordController.text,
            allowedClassId: _role == UserRole.facilitator ? _selectedClassId : null,
            allowedMode: _role == UserRole.facilitator && _selectedMode != null && _selectedMode!.trim().isNotEmpty
                ? _selectedMode!.trim()
                : null,
          );
      if (_role == UserRole.facilitator) {
        final classRepo = ref.read(classRepositoryProvider);
        final classes = await ref.read(allClassesFutureProvider.future);
        for (final c in classes) {
          if (c.facilitatorUserId == widget.user.id) {
            await classRepo.updateFacilitator(c.id, null);
          }
        }
      }
      if (mounted) {
        widget.onSaved();
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceFirst('UserRepositoryException: ', ''))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor = isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    ref.listen(classesForFacilitatorUserIdProvider(widget.user.id), (prev, next) {
      next.whenData((classes) {
        if (mounted && !_scopeInitialized && _selectedClassId == null && classes.isNotEmpty) {
          setState(() {
            _scopeInitialized = true;
            _selectedClassId = classes.first.id;
            _selectedMode ??= 'Full-time';
          });
        }
      });
    });

    return AlertDialog(
      title: Text('Edit User: ${widget.user.username}', style: const TextStyle(fontFamily: 'Questrial')),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Display name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<UserRole>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: UserRole.values
                      .map((r) => DropdownMenuItem(value: r, child: Text(r.displayName)))
                      .toList(),
                  onChanged: (r) => setState(() => _role = r ?? UserRole.facilitator),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('Active', style: TextStyle(fontFamily: 'Questrial')),
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v ?? true),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _newPasswordController,
                  decoration: const InputDecoration(
                    labelText: 'New password (leave blank to keep current)',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                if (_role == UserRole.facilitator) ...[
                  const SizedBox(height: 12),
                  const Text('Assigned class and mode', style: TextStyle(fontFamily: 'Questrial', fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  ref.watch(allClassesFutureProvider).when(
                    data: (classes) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<int>(
                          initialValue: _selectedClassId,
                          decoration: const InputDecoration(
                            labelText: 'Class',
                            border: OutlineInputBorder(),
                          ),
                          items: classes
                              .map<DropdownMenuItem<int>>((SchoolClass c) => DropdownMenuItem<int>(value: c.id, child: Text(c.name)))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedClassId = v),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedMode ?? _modeOptions.first,
                          decoration: const InputDecoration(
                            labelText: 'Mode',
                            border: OutlineInputBorder(),
                          ),
                          items: _modeOptions
                              .map((m) => DropdownMenuItem<String>(value: m, child: Text(m)))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedMode = v),
                        ),
                      ],
                    ),
                    loading: () => const SizedBox(height: 24, child: Center(child: CircularProgressIndicator())),
                    error: (e, _) => Text('Error loading classes: $e', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          style: FilledButton.styleFrom(backgroundColor: redColor),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
