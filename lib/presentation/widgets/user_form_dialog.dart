import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';

/// Dialog to add a new user.
class UserFormDialog extends ConsumerStatefulWidget {
  const UserFormDialog({super.key, required this.onSaved});

  final VoidCallback onSaved;

  static Future<void> show({required BuildContext context, required WidgetRef ref, required VoidCallback onSaved}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Consumer(
        builder: (context, ref, _) => UserFormDialog(onSaved: onSaved),
      ),
    );
  }

  @override
  ConsumerState<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends ConsumerState<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  UserRole _role = UserRole.facilitator;
  final Set<int> _selectedClassIds = {};

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final newUserId = await ref.read(userRepositoryProvider).createUser(
            username: _usernameController.text.trim(),
            plainPassword: _passwordController.text,
            displayName: _displayNameController.text.trim().isEmpty ? null : _displayNameController.text.trim(),
            role: _role,
          );
      if (_role == UserRole.facilitator && _selectedClassIds.isNotEmpty) {
        final classRepo = ref.read(classRepositoryProvider);
        for (final classId in _selectedClassIds) {
          await classRepo.updateFacilitator(classId, newUserId);
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

    return AlertDialog(
      title: const Text('Add User', style: TextStyle(fontFamily: 'Questrial')),
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
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                  ),
                  obscureText: true,
                  validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Display name (optional)',
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
          child: const Text('Add User'),
        ),
      ],
    );
  }
}
