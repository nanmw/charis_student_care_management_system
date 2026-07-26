import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/core/theme/app_colors.dart';
import 'package:charis_student_care/data/database/app_database.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/providers/class_providers.dart';
import 'package:charis_student_care/presentation/providers/student_providers.dart';
import 'package:charis_student_care/presentation/providers/sync_providers.dart';
import 'package:charis_student_care/presentation/providers/theme_mode_provider.dart';
import 'package:charis_student_care/presentation/providers/user_management_providers.dart';
import 'package:charis_student_care/presentation/theme/app_table_style.dart';
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
          headingRowColor: AppTableStyle.dataTableHeadingColor(colorScheme),
          headingTextStyle: AppTableStyle.headerTextStyle(colorScheme),
          dataTextStyle: AppTableStyle.bodyTextStyle(colorScheme),
          dividerThickness: 1,
          columns: const [
            DataColumn(label: Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('Username', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Questrial')))),
            DataColumn(label: Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('Display name', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Questrial')))),
            DataColumn(label: Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('Role', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Questrial')))),
            DataColumn(label: Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('Assigned class(es)', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Questrial')))),
            DataColumn(label: Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('Active', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Questrial')))),
            DataColumn(label: Padding(padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6), child: Text('Actions', style: TextStyle(fontWeight: FontWeight.w600, fontFamily: 'Questrial')))),
          ],
          rows: users.map((user) {
            final role = UserRole.fromString(user.role);
            return DataRow(
              cells: [
                DataCell(Padding(padding: AppTableStyle.cellPadding, child: Text(user.username, style: const TextStyle(fontFamily: 'Questrial')))),
                DataCell(Padding(padding: AppTableStyle.cellPadding, child: Text(user.displayName ?? '—', style: const TextStyle(fontFamily: 'Questrial')))),
                DataCell(Padding(padding: AppTableStyle.cellPadding, child: Text(role.displayName, style: const TextStyle(fontFamily: 'Questrial')))),
                DataCell(
                  Padding(
                    padding: AppTableStyle.cellPadding,
                    child: role == UserRole.facilitator
                        ? _AssignedClassesCell(user: user)
                        : const Text('—', style: TextStyle(fontFamily: 'Questrial',),),
                  ),
                ),
                DataCell(Padding(padding: AppTableStyle.cellPadding, child: Text(user.isActive ? 'Yes' : 'No', style: const TextStyle(fontFamily: 'Questrial')))),
                DataCell(
                  Padding(
                    padding: AppTableStyle.cellPadding,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          onPressed: () => openEditUser(context, ref, user),
                          icon: const Icon(Icons.edit_outlined, size: 14),
                          label: const Text('Edit'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.all(6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => toggleActive(context, ref, user),
                          icon: Icon(user.isActive ? Icons.block : Icons.check_circle_outline, size: 14),
                          label: Text(user.isActive ? 'Deactivate' : 'Activate'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.all(6),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton.icon(
                          onPressed: () => deleteUser(context, ref, user),
                          icon: const Icon(Icons.delete_outlined, size: 14),
                          label: const Text('Delete'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.all(6),
                          ),
                        ),
                      ],
                    ),
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

/// Shows assigned class and mode for a facilitator user (e.g. "Year 1 • Hybrid").
class _AssignedClassesCell extends ConsumerWidget {
  const _AssignedClassesCell({required this.user});

  final User user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (UserRole.fromString(user.role) != UserRole.facilitator) {
      return const Text('—', style: TextStyle(fontFamily: 'Questrial'));
    }
    if (user.allowedClassId != null) {
      final classAsync = ref.watch(classByIdProvider(user.allowedClassId!));
      return classAsync.when(
        data: (SchoolClass? c) => Text(
          c == null ? '—' : '${c.name} • ${user.allowedMode ?? '—'}',
          style: const TextStyle(fontFamily: 'Questrial'),
        ),
        loading: () => const Text('...', style: TextStyle(fontFamily: 'Questrial')),
        error: (_, __) => const Text('—', style: TextStyle(fontFamily: 'Questrial')),
      );
    }
    final async = ref.watch(classesForFacilitatorUserIdProvider(user.id));
    return async.when(
      data: (classes) => Text(
        classes.isEmpty ? '—' : classes.map((SchoolClass c) => c.name).join(', '),
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
        final auth = ref.read(authStateProvider).valueOrNull;
        if (auth is! Authenticated) return;
        await ref.read(userRepositoryProvider).setActive(
              user.id,
              !user.isActive,
              actorRole: auth.role,
            );
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

Future<void> deleteUser(BuildContext context, WidgetRef ref, User user) async {
  final auth = ref.read(authStateProvider).valueOrNull;
  if (auth is Authenticated && auth.user.id == user.id.toString()) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('You cannot delete your own account')),
    );
    return;
  }
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(
        'Delete user?',
        style: TextStyle(fontFamily: 'Questrial'),
      ),
      content: Text(
        '${user.username} will be permanently removed. This cannot be undone.',
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
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    try {
      final authForDelete = ref.read(authStateProvider).valueOrNull;
      if (authForDelete is! Authenticated) return;
      final deviceId = await ref.read(deviceIdProvider.future);
      await ref.read(userRepositoryProvider).deleteUser(
            user.id,
            actorRole: authForDelete.role,
            userId: authForDelete.user.id,
            deviceId: deviceId,
            userDisplayName: authForDelete.user.displayName,
            screen: 'Users',
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User deleted')),
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
