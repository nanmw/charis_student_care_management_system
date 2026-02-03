import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';

/// Shows [child] only when the current user's role satisfies [canShow].
/// Otherwise shows [placeholder] (default: nothing).
class RoleGuard extends ConsumerWidget {
  const RoleGuard({
    super.key,
    required this.canShow,
    required this.child,
    this.placeholder = const SizedBox.shrink(),
  });

  final bool Function(UserRole role) canShow;
  final Widget child;
  final Widget placeholder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateProvider);
    final auth = authAsync.valueOrNull;
    if (auth is! Authenticated) return placeholder;
    if (!canShow(auth.role)) return placeholder;
    return child;
  }
}
