import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

class AuthState {
  final User? user;
  final bool isLoading;
  final String? errorMessage;

  AuthState({this.user, this.isLoading = false, this.errorMessage});
}

// SWITCH TO 'Notifier' (Built-in to Riverpod 2.0)
class AuthController extends Notifier<AuthState> {
  // 1. Initialize State (Replaces Constructor)
  @override
  AuthState build() {
    return AuthState();
  }

  // 2. Login Logic
  Future<void> login(String email, String password) async {
    state = AuthState(isLoading: true);

    // We can read providers directly using 'ref' inside the method
    final authService = ref.read(authServiceProvider);
    final user = await authService.login(email, password);

    if (user != null) {
      state = AuthState(user: user, isLoading: false);
    } else {
      state = AuthState(
        isLoading: false,
        errorMessage: "Login Failed. Check credentials.",
      );
    }
  }

  // 3. Signup Logic
  Future<bool> signUp(String username, String email, String password) async {
    state = AuthState(isLoading: true);
    final authService = ref.read(authServiceProvider);
    final success = await authService.register(username, email, password);
    state = AuthState(isLoading: false);
    return success;
  }

  // 4. Logout Logic
  void logout() {
    ref.read(authServiceProvider).logout();
    state = AuthState();
  }
}

// CHANGE PROVIDER TYPE TO 'NotifierProvider'
final authProvider = NotifierProvider<AuthController, AuthState>(() {
  return AuthController();
});
