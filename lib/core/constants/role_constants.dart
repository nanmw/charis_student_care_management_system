/// Role definitions and permissions
enum UserRole {
  facilitator('Facilitator'),
  adminLevel02('Admin Level 02'),
  adminLevel01('Admin Level 01');

  const UserRole(this.displayName);
  final String displayName;
}

/// Role permissions helper
class RolePermissions {
  RolePermissions._();

  /// Check if role can add/edit students
  static bool canManageStudents(UserRole role) {
    return role == UserRole.adminLevel01 || role == UserRole.adminLevel02;
  }

  /// Check if role can manage financials (payments)
  static bool canManageFinancials(UserRole role) {
    return role == UserRole.adminLevel01;
  }

  /// Check if role can enter attendance
  static bool canEnterAttendance(UserRole role) {
    return true; // All roles can enter attendance
  }

  /// Check if role can enter tests
  static bool canEnterTests(UserRole role) {
    return true; // All roles can enter tests
  }

  /// Check if role can resolve sync conflicts
  static bool canResolveConflicts(UserRole role) {
    return role == UserRole.adminLevel01;
  }
}
