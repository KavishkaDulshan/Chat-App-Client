import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/e2ee_service.dart';
import '../providers/socket_provider.dart';
import '../providers/local_db_provider.dart';

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
  Future<void> _bootstrapE2EE(User user, {String? password}) async {
    try {
      final e2eeService = ref.read(e2eeServiceProvider);
      final authService = ref.read(authServiceProvider);

      // Derive or retrieve the AES lookup key for E2E backup
      final backupKeyB64 = await e2eeService.getOrDeriveBackupKey(
        password: password,
        salt: user.email,
      );

      // ensureIdentityKeyForUser will:
      //   1. Use local keys if available
      //   2. Restore from server (decrypting if backupKeyB64 is provided)
      //   3. Generate new keys only as a last resort
      final publicKey = await e2eeService.ensureIdentityKeyForUser(
        user.id,
        serverKeyFetcher: () => authService.fetchMyE2EEKeyPair(),
        backupKeyB64: backupKeyB64,
      );

      // We must encrypt the private key before upload
      String? privateKeyToUpload = await e2eeService.getMyPrivateKey();
      if (privateKeyToUpload != null && backupKeyB64 != null) {
        final encryptedPriv = await e2eeService.encryptPrivateKeyBackup(privateKeyToUpload, backupKeyB64);
        if (encryptedPriv != null) {
          privateKeyToUpload = encryptedPriv;
        }
      }

      await authService.uploadE2EEPublicKey(
        publicKey,
        privateKey: privateKeyToUpload,
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

  // Helper to initialize local database for the logged-in user
  Future<void> _initLocalDatabase(User user) async {
    final db = await initLocalDb(user.id);
    ref.read(localDbProvider.notifier).state = db;
  }

  Future<void> checkAuthStatus() async {
    state = AuthState(isLoading: true);
    final authService = ref.read(authServiceProvider);
    final user = await authService.tryAutoLogin();

    if (user != null) {
      // Auto-login does not have the password, so backupKey is fetched from secure storage
      await _bootstrapE2EE(user);
      _connectSocket(user);
      await _initLocalDatabase(user);
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
      // Pass the password to bootstrap so we can derive the key
      await _bootstrapE2EE(user, password: password);
      _connectSocket(user);
      await _initLocalDatabase(user);
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
      // 1. Close local database
      await closeLocalDb(ref.read(localDbProvider));
      ref.read(localDbProvider.notifier).state = null;

      // 2. Try to disconnect socket
      ref.read(socketServiceProvider).disconnect();

      // 3. Try to notify server
      await ref.read(authServiceProvider).logout();
    } catch (e) {
      print("Logout Warning: $e");
    } finally {
      // 4. ALWAYS clear local state, even if errors occur above
      state = AuthState();
    }
  }

  Future<bool> verifyOTP(String email, String otp, String password) async {
    state = AuthState(isLoading: true);
    final authService = ref.read(authServiceProvider);

    final user = await authService.verifyOTP(email, otp);

    if (user != null) {
      // Pass the password to bootstrap so we can derive the key
      await _bootstrapE2EE(user, password: password);
      _connectSocket(user);
      await _initLocalDatabase(user);
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
