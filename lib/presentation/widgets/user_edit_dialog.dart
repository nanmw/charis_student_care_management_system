import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
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

class _UserEditDialogState extends ConsumerState<UserEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _displayNameController;
  late UserRole _role;
  late bool _isActive;
  final _newPasswordController = TextEditingController();
  final Set<int> _selectedClassIds = {};
  Set<int> _initialAssignedClassIds = {};

  @override
  void initState() {
    super.initState();
    _displayNameController = TextEditingController(text: widget.user.displayName ?? '');
    _role = UserRole.fromString(widget.user.role);
    _isActive = widget.user.isActive;
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
          );
      final classRepo = ref.read(classRepositoryProvider);
      if (_role != UserRole.facilitator) {
        for (final classId in _initialAssignedClassIds) {
          await classRepo.updateFacilitator(classId, null);
        }
      } else {
        for (final classId in _initialAssignedClassIds) {
          if (!_selectedClassIds.contains(classId)) {
            await classRepo.updateFacilitator(classId, null);
          }
        }
        for (final classId in _selectedClassIds) {
          if (!_initialAssignedClassIds.contains(classId)) {
            await classRepo.updateFacilitator(classId, widget.user.id);
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
        if (mounted && _initialAssignedClassIds.isEmpty) {
          setState(() {
            _initialAssignedClassIds = classes.map((c) => c.id).toSet();
            _selectedClassIds.addAll(_initialAssignedClassIds);
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
                  const Text('Assigned class(es)', style: TextStyle(fontFamily: 'Questrial', fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  ref.watch(allClassesFutureProvider).when(
                    data: (classes) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: classes.map((c) => CheckboxListTile(
                        title: Text(c.name, style: const TextStyle(fontFamily: 'Questrial')),
                        value: _selectedClassIds.contains(c.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedClassIds.add(c.id);
                          } else {
                            _selectedClassIds.remove(c.id);
                          }
                        }),
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ), ).toList(),
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
