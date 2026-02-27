import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/providers/user_management_providers.dart';
import 'package:charis_student_care/presentation/widgets/common/role_guard.dart';
import 'package:charis_student_care/presentation/widgets/user_edit_dialog.dart';
import 'package:charis_student_care/presentation/widgets/user_form_dialog.dart';

/// User management screen: list users, add, edit, activate/deactivate. Admin Level 01 only.
class UserManagementScreen extends ConsumerWidget {
  const UserManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const RoleGuard(
      canShow: RolePermissions.canManageUsers,
      placeholder: Center(child: Text('You do not have permission to manage users.')),
      child: _UserManagementContent(),
    );
  }
}

class _UserManagementContent extends ConsumerWidget {
  const _UserManagementContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final themeMode = ref.watch(themeModeProvider);
    final isDark = themeMode == ThemeMode.dark;
    final redColor = isDark ? AppColors.primaryActionRed : AppColors.charisRedPrimary;
    final usersAsync = ref.watch(usersStreamProvider);

    return Container(
      color: colorScheme.surface,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'User Management',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 24,
                  fontFamily: 'Questrial',
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _openAddUser(context, ref),
                icon: const Icon(Icons.add, size: 20),
                label: const Text('Add User'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: redColor,
                  foregroundColor: AppColors.charisWhite,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: usersAsync.when(
              data: (users) {
                if (users.isEmpty) {
                  return Center(
                    child: Text(
                      'No users yet. Add a user to get started.',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 14,
                        fontFamily: 'Questrial',
                      ),
                    ),
                  );
                }
                return _UserManagementContent._buildTable(context, ref, users, colorScheme);
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Error loading users: $e',
                  style: TextStyle(color: colorScheme.error, fontFamily: 'Questrial',),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _buildTable(
      BuildContext context, WidgetRef ref, List<User> users, ColorScheme colorScheme,) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(colorScheme.surfaceContainerHighest),
          columns: const [
            DataColumn(label: Text('Username', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Questrial'))),
            DataColumn(label: Text('Display name', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Questrial'))),
            DataColumn(label: Text('Role', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Questrial'))),
            DataColumn(label: Text('Assigned class(es)', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Questrial'))),
            DataColumn(label: Text('Active', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Questrial'))),
            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Questrial'))),
          ],
          rows: users.map((user) {
            final role = UserRole.fromString(user.role);
            return DataRow(
              cells: [
                DataCell(Text(user.username, style: const TextStyle(fontFamily: 'Questrial'))),
                DataCell(Text(user.displayName ?? '—', style: const TextStyle(fontFamily: 'Questrial'))),
                DataCell(Text(role.displayName, style: const TextStyle(fontFamily: 'Questrial'))),
                DataCell(
                  role == UserRole.facilitator
                      ? _AssignedClassesCell(userId: user.id)
                      : const Text('—', style: TextStyle(fontFamily: 'Questrial',),),
                ),
                DataCell(Text(user.isActive ? 'Yes' : 'No', style: const TextStyle(fontFamily: 'Questrial'))),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton.icon(
                        onPressed: () => openEditUser(context, ref, user),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edit'),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: () => toggleActive(context, ref, user),
                        icon: Icon(user.isActive ? Icons.block : Icons.check_circle_outline, size: 18),
                        label: Text(user.isActive ? 'Deactivate' : 'Activate'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

}

/// Shows assigned class names for a facilitator user.
class _AssignedClassesCell extends ConsumerWidget {
  const _AssignedClassesCell({required this.userId});

  final int userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(classesForFacilitatorUserIdProvider(userId));
    return async.when(
      data: (classes) => Text(
        classes.isEmpty ? '—' : classes.map((c) => c.name).join(', '),
        style: const TextStyle(fontFamily: 'Questrial'),
      ),
      loading: () => const Text('...', style: TextStyle(fontFamily: 'Questrial')),
      error: (_, __) => const Text('—', style: TextStyle(fontFamily: 'Questrial')),
    );
  }
}

void _openAddUser(BuildContext context, WidgetRef ref) {
  UserFormDialog.show(
    context: context,
    ref: ref,
    onSaved: () {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User added successfully')),
      );
    },
  );
}

void openEditUser(BuildContext context, WidgetRef ref, User user) {
  UserEditDialog.show(
    context: context,
    ref: ref,
    user: user,
    onSaved: () {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User updated successfully')),
      );
    },
  );
}

Future<void> toggleActive(BuildContext context, WidgetRef ref, User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          user.isActive ? 'Deactivate user?' : 'Activate user?',
          style: const TextStyle(fontFamily: 'Questrial'),
        ),
        content: Text(
          user.isActive
              ? '${user.username} will not be able to log in until activated again.'
              : '${user.username} will be able to log in again.',
          style: const TextStyle(fontFamily: 'Questrial'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.charisRedPrimary),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      try {
        await ref.read(userRepositoryProvider).setActive(user.id, !user.isActive);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(user.isActive ? 'User deactivated' : 'User activated')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }
