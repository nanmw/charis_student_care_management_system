import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/repository_providers.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';
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

const List<String> _modeOptions = ['Full-time', 'Hybrid'];

class _UserFormDialogState extends ConsumerState<UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _displayNameController = TextEditingController();
  UserRole _role = UserRole.facilitator;
  int? _selectedClassId;
  String? _selectedMode = 'Full-time';

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
      final auth = ref.read(authStateProvider).valueOrNull;
      final deviceId = await ref.read(deviceIdProvider.future);
      await ref.read(userRepositoryProvider).createUser(
            username: _usernameController.text.trim(),
            plainPassword: _passwordController.text,
            displayName: _displayNameController.text.trim().isEmpty ? null : _displayNameController.text.trim(),
            role: _role,
            allowedClassId: _role == UserRole.facilitator ? _selectedClassId : null,
            allowedMode: _role == UserRole.facilitator && _selectedMode != null && _selectedMode!.trim().isNotEmpty
                ? _selectedMode!.trim()
                : null,
            actorRole: (auth as Authenticated?)?.role ?? UserRole.facilitator,
            userId: auth is Authenticated ? auth.user.id : null,
            deviceId: deviceId,
            userDisplayName: auth is Authenticated ? auth.user.displayName : null,
            screen: 'Users',
          );
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
          child: const Text('Add User'),
        ),
      ],
    );
  }
}
