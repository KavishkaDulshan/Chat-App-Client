import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../providers/socket_provider.dart'; // Import Socket Provider

class AuthState {
  final User? user;
  final bool isLoading;
  final String? errorMessage;

  AuthState({this.user, this.isLoading = false, this.errorMessage});
}

final authProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    return AuthState(isLoading: true);
  }

  // Helper to connect socket
  void _connectSocket(User user) {
    final socketService = ref.read(socketServiceProvider);
    socketService.connect(user, () {
      print("Socket Connected via AuthProvider");
    });
  }

  Future<void> checkAuthStatus() async {
    state = AuthState(isLoading: true);
    final authService = ref.read(authServiceProvider);
    final user = await authService.tryAutoLogin();

    if (user != null) {
      // FIX: Connect socket immediately after restoring user
      _connectSocket(user);
      state = AuthState(user: user, isLoading: false);
    } else {
      state = AuthState(isLoading: false);
    }
  }

  Future<void> login(String email, String password) async {
    state = AuthState(isLoading: true);
    final authService = ref.read(authServiceProvider);
    final user = await authService.login(email, password);

    if (user != null) {
      // FIX: Connect socket after manual login
      _connectSocket(user);
      state = AuthState(user: user, isLoading: false);
    } else {
      state = AuthState(
        isLoading: false,
        errorMessage: "Login Failed. Check credentials.",
      );
    }
  }

  Future<bool> signUp(String username, String email, String password) async {
    state = AuthState(isLoading: true);
    final authService = ref.read(authServiceProvider);
    final success = await authService.register(username, email, password);
    state = AuthState(isLoading: false);
    return success;
  }

  Future<void> logout() async {
    // FIX: Disconnect socket on logout
    ref.read(socketServiceProvider).disconnect();
    await ref.read(authServiceProvider).logout();
    state = AuthState();
  }
}
