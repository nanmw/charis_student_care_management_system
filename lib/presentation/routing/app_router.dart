import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:charis_student_care/core/constants/role_constants.dart';
import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/widgets/shell/app_shell.dart';
import '../screens/attendance_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../screens/payments_screen.dart';
import '../screens/ministry_hours_screen.dart';
import '../screens/export_reports_screen.dart';
import '../screens/mission_locations_screen.dart';
import '../screens/missions_payment_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/student_list_screen.dart';
import '../screens/subjects_screen.dart';
import '../screens/tests_screen.dart';
import '../screens/user_management_screen.dart';

/// Application routing configuration with auth redirect.
final goRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(authRefreshNotifierProvider);
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final authAsync = ref.read(authStateProvider);
      return authAsync.when(
        data: (auth) {
          if (auth is Unauthenticated && state.matchedLocation != '/login') {
            return '/login';
          }
          if (auth is Authenticated && state.matchedLocation == '/login') {
            return '/dashboard';
          }
          // Facilitators must not access Payments or Missions Payment screens; redirect to dashboard.
          if (auth is Authenticated &&
              auth.role == UserRole.facilitator &&
              (state.matchedLocation == '/payments' || state.matchedLocation == '/missions-payment')) {
            return '/dashboard';
          }
          // Only roles with report permission can access Export & Reports.
          if (auth is Authenticated &&
              !RolePermissions.canExportReports(auth.role) &&
              state.matchedLocation == '/reports') {
            return '/dashboard';
          }
          return null;
        },
        loading: () => null,
        error: (_, __) => '/login',
      );
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      // Shell (header, sidebar, footer) is shared by all routes below; add new screens here to show them inside the shell.
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => const DashboardScreen(),
          ),
          GoRoute(
            path: '/students',
            builder: (context, state) => const StudentListScreen(),
          ),
          GoRoute(
            path: '/subjects',
            builder: (context, state) => const SubjectsScreen(),
          ),
          GoRoute(
            path: '/attendance',
            builder: (context, state) => const AttendanceScreen(),
          ),
          GoRoute(
            path: '/ministry-hours',
            builder: (context, state) => const MinistryHoursScreen(),
          ),
          GoRoute(
            path: '/tests',
            builder: (context, state) => const TestsScreen(),
          ),
          GoRoute(
            path: '/payments',
            builder: (context, state) => const PaymentsScreen(),
          ),
          GoRoute(
            path: '/mission-locations',
            builder: (context, state) => const MissionLocationsScreen(),
          ),
          GoRoute(
            path: '/missions-payment',
            builder: (context, state) => const MissionsPaymentScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => ExportReportsScreen(
              initialReportType: state.uri.queryParameters['type'],
            ),
          ),
          GoRoute(
            path: '/users',
            builder: (context, state) => const UserManagementScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
});
