import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/api_client.dart';
import '../services/session_bootstrap_service.dart';
import '../providers/socket_provider.dart';
import '../providers/conversations_provider.dart';
import '../providers/contact_provider.dart';
import '../providers/chat_provider.dart';

class AuthState {
  final User? user;
  final bool isLoading;
  final bool isInitializing;
  final String? errorMessage;

  AuthState({
    this.user,
    this.isLoading = false,
    this.isInitializing = false,
    this.errorMessage,
  });
}

final authProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

class AuthController extends Notifier<AuthState> {
  final _storage = const FlutterSecureStorage();

  @override
  AuthState build() {
    // Register the forced-logout callback with ApiClient so it can trigger
    // logout when a token refresh fails inside the Dio interceptor.
    onForceLogout = _handleForceLogout;
    return AuthState(isInitializing: true);
  }

  // ─── Socket auth error → try refresh → reconnect or logout ───────────────
  Future<void> _handleSocketAuthError(String errorCode) async {
    print('⚠️ Socket auth error: $errorCode');
    if (errorCode == 'TOKEN_EXPIRED') {
      await _tryRefreshThenReconnect();
    } else {
      // Truly invalid token — force logout
      await logout();
    }
  }

  Future<void> _tryRefreshThenReconnect() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) {
        await logout();
        return;
      }

      final authService = ref.read(authServiceProvider);
      // Use the silent refresh path in auth_service
      // We call silently — if it updates secure storage we'll read the new token
      final newToken = await authService.tryAutoLogin();
      if (newToken == null) {
        await logout();
        return;
      }

      // Re-read the fresh access token from secure storage
      final freshToken = await _storage.read(key: 'jwt_token');
      if (freshToken == null) {
        await logout();
        return;
      }

      // Reconnect socket with the new token
      ref.read(socketServiceProvider).reconnectWithNewToken(freshToken);
      print('✅ Socket reconnected with refreshed token');
    } catch (e) {
      print('Token refresh + reconnect failed: $e');
      await logout();
    }
  }

  /// Called by ApiClient.onForceLogout when a Dio interceptor refresh fails.
  void _handleForceLogout() {
    print('⚠️ Forced logout triggered by token refresh failure');
    // Schedule on next microtask to avoid calling during a build cycle
    Future.microtask(() => logout());
  }

  // ─── Socket reconnect → resync data ──────────────────────────────────────
  void _handleSocketReconnected() {
    print('🔄 Socket reconnected — resyncing data');
    try {
      ref.read(conversationsProvider.notifier).loadChats(forceRefresh: true);
    } catch (_) {}
    try {
      ref.read(chatProvider.notifier).resyncActiveRoom();
    } catch (_) {}
  }

  // ─── Check auth status (app start) ───────────────────────────────────────
  Future<void> checkAuthStatus() async {
    state = AuthState(isInitializing: true);
    final authService = ref.read(authServiceProvider);
    final user = await authService.tryAutoLogin();

    if (user != null) {
      // Show home screen immediately from local data
      state = AuthState(user: user, isLoading: false);

      // Initialize session in background
      await ref.read(sessionBootstrapServiceProvider).initSession(
        user,
        onSocketAuthError: _handleSocketAuthError,
        onSocketReconnected: _handleSocketReconnected,
      );
    } else {
      state = AuthState(isInitializing: false, isLoading: false);
    }
  }

  // ─── Login ────────────────────────────────────────────────────────────────
  Future<void> login(String email, String password) async {
    state = AuthState(isLoading: true);
    final authService = ref.read(authServiceProvider);
    final user = await authService.login(email, password);

    if (user != null) {
      await ref.read(sessionBootstrapServiceProvider).initSession(
        user,
        password: password,
        onSocketAuthError: _handleSocketAuthError,
        onSocketReconnected: _handleSocketReconnected,
      );
      state = AuthState(user: user, isLoading: false, isInitializing: false);
    } else {
      state = AuthState(
        isLoading: false,
        errorMessage: 'Login Failed. Check credentials.',
      );
    }
  }

  // ─── Verify OTP (new registration) ───────────────────────────────────────
  Future<bool> verifyOTP(String email, String otp, String password) async {
    state = AuthState(isLoading: true);
    final authService = ref.read(authServiceProvider);
    final user = await authService.verifyOTP(email, otp);

    if (user != null) {
      await ref.read(sessionBootstrapServiceProvider).initSession(
        user,
        password: password,
        onSocketAuthError: _handleSocketAuthError,
        onSocketReconnected: _handleSocketReconnected,
      );
      state = AuthState(user: user, isLoading: false);
      return true;
    } else {
      state = AuthState(
        isLoading: false,
        errorMessage: 'Invalid OTP or Expired.',
      );
      return false;
    }
  }

  // ─── Sign Up ──────────────────────────────────────────────────────────────
  Future<bool> signUp(String username, String email, String password) async {
    state = AuthState(isLoading: true);
    final authService = ref.read(authServiceProvider);
    final success = await authService.register(username, email, password);
    state = AuthState(isLoading: false);
    return success;
  }

  // ─── Logout ───────────────────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      // 1. Teardown session (DB + socket + E2EE)
      await ref.read(sessionBootstrapServiceProvider).teardownSession();

      // 2. Tell server to invalidate this device's refresh token
      await ref.read(authServiceProvider).logout();

      // 3. Invalidate dependent providers to clear in-memory state
      //    This is now safe because the socket is already disconnected in teardownSession
      ref.invalidate(conversationsProvider);
      ref.invalidate(contactProvider);
      ref.invalidate(chatProvider);
    } catch (e) {
      print('Logout Warning: $e');
    } finally {
      // ALWAYS clear local state, even if errors occur above
      state = AuthState();
    }
  }

  /// Directly update the user in state (e.g. after profile edits).
  /// Does NOT re-bootstrap E2EE or reconnect socket.
  void setUser(User user) {
    state = AuthState(user: user, isLoading: false);
  }
}
