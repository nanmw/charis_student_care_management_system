import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:charis_student_care/presentation/providers/auth_provider.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';
import 'package:charis_student_care/presentation/widgets/shell/app_shell.dart';
import '../screens/attendance_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/login_screen.dart';
import '../screens/payments_screen.dart';
import '../screens/placeholder_screen.dart';
import '../screens/student_list_screen.dart';
import '../screens/tests_screen.dart';

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
            path: '/attendance',
            builder: (context, state) => const AttendanceScreen(),
          ),
          GoRoute(
            path: '/ministry-hours',
            builder: (context, state) => const PlaceholderScreen(),
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
            path: '/missions',
            builder: (context, state) => const PlaceholderScreen(),
          ),
          GoRoute(
            path: '/reports',
            builder: (context, state) => const PlaceholderScreen(),
          ),
        ],
      ),
    ],
  );
});
