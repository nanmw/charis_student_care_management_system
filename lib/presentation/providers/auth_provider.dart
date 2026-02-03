import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:charis_student_care/core/config/auth_config.dart';
import 'package:charis_student_care/data/services/auth_service.dart';
import 'package:charis_student_care/presentation/providers/auth_state.dart';

/// Listenable for router refresh when auth state changes.
class AuthRefreshNotifier extends ChangeNotifier {
  void refresh() => notifyListeners();
}

final authRefreshNotifierProvider = Provider<AuthRefreshNotifier>((ref) {
  return AuthRefreshNotifier();
});

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authStateProvider =
    AsyncNotifierProvider<AuthNotifier, AuthState>(AuthNotifier.new);

class AuthNotifier extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    final service = ref.read(authServiceProvider);
    await service.restoreSession();
    final authState = _stateFromService(service);
    // When skip-auth is on, we're "logged in" immediately; notify router so it redirects from /login to /students.
    if (AuthConfig.skipAuth && authState is Authenticated) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _notifyRefresh();
      });
    }
    return authState;
  }

  Future<void> signIn() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final service = ref.read(authServiceProvider);
      await service.login();
      _notifyRefresh();
      return _stateFromService(service);
    });
  }

  void signOut() {
    ref.read(authServiceProvider).logout();
    state = const AsyncValue.data(Unauthenticated());
    _notifyRefresh();
  }

  AuthState _stateFromService(AuthService service) {
    if (!service.isAuthenticated || service.user == null) {
      return const Unauthenticated();
    }
    return Authenticated(
      user: service.user!,
      role: service.getRole(),
    );
  }

  void _notifyRefresh() {
    ref.read(authRefreshNotifierProvider).refresh();
  }
}
