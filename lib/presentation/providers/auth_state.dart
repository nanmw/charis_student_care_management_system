import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/data/models/auth_user.dart';

/// Auth state: either unauthenticated or authenticated with user and role.
sealed class AuthState {
  const AuthState();
}

/// Not signed in.
class Unauthenticated extends AuthState {
  const Unauthenticated();
}

/// Signed in with user and role.
class Authenticated extends AuthState {
  const Authenticated({required this.user, required this.role});

  final AuthUser user;
  final UserRole role;
}
