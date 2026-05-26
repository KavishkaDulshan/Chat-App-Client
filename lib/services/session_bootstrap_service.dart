import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../providers/local_db_provider.dart';
import '../providers/socket_provider.dart';
import '../services/auth_service.dart';
import '../services/e2ee_service.dart';

final sessionBootstrapServiceProvider = Provider<SessionBootstrapService>((ref) {
  return SessionBootstrapService(ref);
});

/// Manages the full session lifecycle: socket connection, local DB init, and E2EE bootstrap.
/// auth_provider delegates to this service so it can stay focused on auth state only.
class SessionBootstrapService {
  final Ref _ref;

  SessionBootstrapService(this._ref);

  // ─── Bootstrap E2EE keys ─────────────────────────────────────────────────
  Future<void> bootstrapE2EE(User user, {String? password}) async {
    try {
      final e2eeService = _ref.read(e2eeServiceProvider);
      final authService = _ref.read(authServiceProvider);

      // Derive or retrieve the AES lookup key for E2E backup
      final backupKeyB64 = await e2eeService.getOrDeriveBackupKey(
        password: password,
        salt: user.email,
      );

      // ensureIdentityKeyForUser:
      //   1. Uses local keys if available
      //   2. Restores from server (decrypting if backupKeyB64 is provided)
      //   3. Generates new keys only as a last resort
      final publicKey = await e2eeService.ensureIdentityKeyForUser(
        user.id,
        serverKeyFetcher: () => authService.fetchMyE2EEKeyPair(),
        backupKeyB64: backupKeyB64,
      );

      // Encrypt the private key before uploading
      String? privateKeyToUpload = await e2eeService.getMyPrivateKey();
      if (privateKeyToUpload != null && backupKeyB64 != null) {
        final encryptedPriv =
            await e2eeService.encryptPrivateKeyBackup(privateKeyToUpload, backupKeyB64);
        if (encryptedPriv != null) {
          privateKeyToUpload = encryptedPriv;
        }
      }

      await authService.uploadE2EEPublicKey(
        publicKey,
        privateKey: privateKeyToUpload,
        backupKey: backupKeyB64,
      );
    } catch (e) {
      print('E2EE Bootstrap Warning: $e');
    }
  }

  // ─── Connect Socket ──────────────────────────────────────────────────────
  void connectSocket(
    User user, {
    void Function(String errorCode)? onAuthError,
    void Function()? onReconnected,
  }) {
    final socketService = _ref.read(socketServiceProvider);
    socketService.connect(
      user,
      () => print('Socket Connected via SessionBootstrapService'),
      onAuthError: onAuthError,
      onReconnected: onReconnected,
    );
  }

  // ─── Init Local Database ─────────────────────────────────────────────────
  Future<void> initLocalDatabase(User user) async {
    final db = await initLocalDb(user.id);
    _ref.read(localDbProvider.notifier).state = db;
  }

  // ─── Full Session Init (login / auto-login) ──────────────────────────────
  Future<void> initSession(
    User user, {
    String? password,
    void Function(String errorCode)? onSocketAuthError,
    void Function()? onSocketReconnected,
  }) async {
    connectSocket(
      user,
      onAuthError: onSocketAuthError,
      onReconnected: onSocketReconnected,
    );

    // DB init and E2EE bootstrap run concurrently
    await Future.wait([
      initLocalDatabase(user),
      bootstrapE2EE(user, password: password),
    ]);
  }

  // ─── Teardown Session (logout) ───────────────────────────────────────────
  Future<void> teardownSession() async {
    try {
      // 1. Close local database
      final db = _ref.read(localDbProvider);
      await closeLocalDb(db);
      _ref.read(localDbProvider.notifier).state = null;
    } catch (e) {
      print('Local DB teardown warning: $e');
    }

    try {
      // 2. Disconnect socket
      _ref.read(socketServiceProvider).disconnect();
    } catch (e) {
      print('Socket teardown warning: $e');
    }

    try {
      // 3. Clear E2EE identity
      await _ref.read(e2eeServiceProvider).clearIdentity();
    } catch (e) {
      print('E2EE teardown warning: $e');
    }
  }
}
