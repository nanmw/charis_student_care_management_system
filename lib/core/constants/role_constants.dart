/// Role definitions and permissions
enum UserRole {
  facilitator('Facilitator'),
  adminLevel02('Portfolio Lead'),
  adminLevel01('Admin');

  const UserRole(this.displayName);
  final String displayName;

  /// Serialized value stored in DB: facilitator, adminLevel02, adminLevel01
  String get value => switch (this) {
        UserRole.facilitator => 'facilitator',
        UserRole.adminLevel02 => 'adminLevel02',
        UserRole.adminLevel01 => 'adminLevel01',
      };

  static UserRole fromString(String s) {
    return switch (s) {
      'adminLevel01' => UserRole.adminLevel01,
      'adminLevel02' => UserRole.adminLevel02,
      _ => UserRole.facilitator,
    };
  }
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

  /// Check if role can enter ministry hours
  static bool canEnterMinistryHours(UserRole role) {
    return true; // All roles can enter ministry hours
  }

  /// Check if role can enter tests
  static bool canEnterTests(UserRole role) {
    return true; // All roles can enter tests
  }

  /// Check if role can resolve sync conflicts
  static bool canResolveConflicts(UserRole role) {
    return role == UserRole.adminLevel01;
  }

  /// Check if role can manage subjects (add/edit/delete)
  static bool canManageSubjects(UserRole role) {
    return role == UserRole.adminLevel01;
  }

  /// Check if role can manage users (create, edit, deactivate)
  static bool canManageUsers(UserRole role) {
    return role == UserRole.adminLevel01;
  }

  /// Check if role can manage missions (create, edit, deactivate) and participations
  static bool canManageMissions(UserRole role) {
    return role == UserRole.adminLevel01;
  }

  /// Check if role can export reports (access Export & Reports, export from screens or Student Summary modal).
  /// All roles can export; data is scoped by facilitator scope (class + mode) when applicable.
  static bool canExportReports(UserRole role) {
    return true;
  }

  /// Check if role can manage academic sessions (create, edit, set current) on Settings. Admin only.
  static bool canManageAcademicSession(UserRole role) {
    return role == UserRole.adminLevel01;
  }
}
