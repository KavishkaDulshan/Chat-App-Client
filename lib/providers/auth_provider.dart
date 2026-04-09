import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/e2ee_service.dart';
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
  Future<void> _bootstrapE2EE(User user) async {
    try {
      final e2eeService = ref.read(e2eeServiceProvider);
      final authService = ref.read(authServiceProvider);

      // ensureIdentityKeyForUser will:
      //   1. Use local keys if available
      //   2. Restore from server if local keys are missing
      //   3. Generate new keys only as a last resort
      final publicKey = await e2eeService.ensureIdentityKeyForUser(
        user.id,
        serverKeyFetcher: () => authService.fetchMyE2EEKeyPair(),
      );

      // Upload both keys so the server always has a backup for key restoration.
      final privateKey = await e2eeService.getMyPrivateKey();
      await authService.uploadE2EEPublicKey(
        publicKey,
        privateKey: privateKey,
      );
    } catch (e) {
      print('E2EE Bootstrap Warning: $e');
    }
  }

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
      await _bootstrapE2EE(user);
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
      await _bootstrapE2EE(user);
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
    try {
      // 1. Try to disconnect socket
      ref.read(socketServiceProvider).disconnect();

      // 2. Try to notify server
      await ref.read(authServiceProvider).logout();
    } catch (e) {
      print("Logout Warning: $e");
    } finally {
      // 3. ALWAYS clear local state, even if errors occur above
      state = AuthState();
    }
  }

  Future<bool> verifyOTP(String email, String otp) async {
    state = AuthState(isLoading: true);
    final authService = ref.read(authServiceProvider);

    final user = await authService.verifyOTP(email, otp);

    if (user != null) {
      await _bootstrapE2EE(user);
      _connectSocket(user);
      state = AuthState(user: user, isLoading: false);
      return true;
    } else {
      state = AuthState(
        isLoading: false,
        errorMessage: "Invalid OTP or Expired.",
      );
      return false;
    }
  }
}
