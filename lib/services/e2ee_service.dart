import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final e2eeServiceProvider = Provider<E2eeService>((ref) => E2eeService());

class E2eeService {
  static const _privateKeyStorageKey = 'e2e_private_key_b64';
  static const _publicKeyStorageKey = 'e2e_public_key_b64';
  static const _keyOwnerStorageKey = 'e2e_key_owner_user_id';
  static const _protocolInfo = 'blinkchat-e2ee-v1';

  static const _backupKeyStorageKey = 'e2e_backup_key_b64';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final Random _random = Random.secure();

  // ── In-memory caches to avoid repeated Android Keystore reads ──
  List<int>? _cachedPrivateKeyBytes;
  List<int>? _cachedPublicKeyBytes;
  // Derived AES-GCM key per conversation pair (keyed by sorted userId pair)
  final Map<String, SecretKey> _conversationKeyCache = {};

  /// Derives or retrieves the client-side AES key used to encrypt the private key
  /// before it is backed up to the server.
  Future<String?> getOrDeriveBackupKey({String? password, String? salt}) async {
    // 1. Try secure storage first
    final existing = await _storage.read(key: _backupKeyStorageKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    // 2. If we have credentials (during manual login/registration), derive key
    if (password != null && password.isNotEmpty && salt != null && salt.isNotEmpty) {
      final pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: 100000,
        bits: 256,
      );
      final secretKey = await pbkdf2.deriveKey(
        secretKey: SecretKey(utf8.encode(password)),
        nonce: utf8.encode(salt),
      );
      final bytes = await secretKey.extractBytes();
      final backupB64 = base64Encode(bytes);
      await _storage.write(key: _backupKeyStorageKey, value: backupB64);
      return backupB64;
    }

    return null;
  }

  Future<String?> encryptPrivateKeyBackup(String rawPrivateKeyB64, String backupKeyB64) async {
    try {
      final secretKey = SecretKey(base64Decode(backupKeyB64));
      final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
      final secretBox = await _aesGcm.encrypt(
        utf8.encode(rawPrivateKeyB64),
        secretKey: secretKey,
        nonce: nonce,
      );
      final payload = {
        'v': 1,
        'n': base64Encode(secretBox.nonce),
        'c': base64Encode(secretBox.cipherText),
        't': base64Encode(secretBox.mac.bytes),
      };
      return 'aes-gcm:v1:' + base64Encode(utf8.encode(jsonEncode(payload)));
    } catch (_) {
      return null;
    }
  }

  Future<String?> decryptPrivateKeyBackup(String encryptedPayload, String backupKeyB64) async {
    try {
      if (!encryptedPayload.startsWith('aes-gcm:v1:')) return encryptedPayload;
      final encodedPart = encryptedPayload.substring('aes-gcm:v1:'.length);
      final decoded = utf8.decode(base64Decode(encodedPart));
      final map = jsonDecode(decoded);
      if (map is! Map<String, dynamic> || map['v'] != 1) return null;

      final nonce = base64Decode(map['n'] as String);
      final cipherText = base64Decode(map['c'] as String);
      final tag = base64Decode(map['t'] as String);

      final secretKey = SecretKey(base64Decode(backupKeyB64));
      final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(tag));
      final clearBytes = await _aesGcm.decrypt(secretBox, secretKey: secretKey);
      return utf8.decode(clearBytes);
    } catch (_) {
      return null;
    }
  }

  /// Ensures a stable key pair exists for [userId].
  ///
  /// Resolution order:
  ///   1. Local secure storage (fastest)
  ///   2. Server-side backup via [serverKeyFetcher] (cross-device / web restore)
  ///   3. Generate a brand-new key pair (first-time only)
  ///
  /// Returns the base-64 encoded public key.
  Future<String> ensureIdentityKeyForUser(
    String userId, {
    Future<Map<String, dynamic>?> Function()? serverKeyFetcher,
    String? backupKeyB64,
  }) async {
    // If the stored keys belong to a different user, clear them.
    final ownerUserId = await _storage.read(key: _keyOwnerStorageKey);
    if (ownerUserId != null && ownerUserId != userId) {
      await _clearIdentity();
    }

    // ──────────────────────────────────────────────────────
    // 1. Try local secure storage first
    // ──────────────────────────────────────────────────────
    final existingPublicKey = await _storage.read(key: _publicKeyStorageKey);
    final existingPrivateKey = await _storage.read(key: _privateKeyStorageKey);

    if (existingPublicKey != null && existingPrivateKey != null) {
      // Warm the in-memory cache so first decrypt is instant
      _cachedPublicKeyBytes = base64Decode(existingPublicKey);
      _cachedPrivateKeyBytes = base64Decode(existingPrivateKey);
      await _storage.write(key: _keyOwnerStorageKey, value: userId);
      return existingPublicKey;
    }

    // ──────────────────────────────────────────────────────
    // 2. Try to restore from server (handles web/cross-device)
    // ──────────────────────────────────────────────────────
    if (serverKeyFetcher != null) {
      try {
        final serverKeys = await serverKeyFetcher();
        if (serverKeys != null) {
          final serverPub = serverKeys['e2e_public_key'] as String?;
          final serverPriv = serverKeys['e2e_private_key'] as String?;

          if (serverPub != null &&
              serverPub.isNotEmpty &&
              serverPriv != null &&
              serverPriv.isNotEmpty) {
            
            // If the server blob is encrypted, decrypt it locally BEFORE saving
            String? decryptedPriv = serverPriv;
            if (serverPriv.startsWith('aes-gcm:v1:')) {
              if (backupKeyB64 != null) {
                decryptedPriv = await decryptPrivateKeyBackup(serverPriv, backupKeyB64);
              } else {
                decryptedPriv = null; // Cannot restore without password derived key
                print('E2EE: Server backup found, but backupKey is missing (requires login).');
              }
            }

            if (decryptedPriv != null && decryptedPriv.isNotEmpty) {
              await _storage.write(key: _publicKeyStorageKey, value: serverPub);
              await _storage.write(key: _privateKeyStorageKey, value: decryptedPriv);
              await _storage.write(key: _keyOwnerStorageKey, value: userId);
              // Warm in-memory cache
              _cachedPublicKeyBytes = base64Decode(serverPub);
              _cachedPrivateKeyBytes = base64Decode(decryptedPriv);
              print('E2EE: Restored key pair from encrypted server backup.');
              return serverPub;
            }
          }
        }
      } catch (e) {
        print('E2EE: Server key restore failed — $e');
      }
    }

    // ──────────────────────────────────────────────────────
    // 3. Generate brand-new key pair (first-time registration)
    // ──────────────────────────────────────────────────────
    final keyPair = await _x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

    final publicB64 = base64Encode(publicKey.bytes);
    final privateB64 = base64Encode(privateKeyBytes);

    await _storage.write(key: _publicKeyStorageKey, value: publicB64);
    await _storage.write(key: _privateKeyStorageKey, value: privateB64);
    await _storage.write(key: _keyOwnerStorageKey, value: userId);

    // Warm up in-memory cache immediately after generation
    _cachedPrivateKeyBytes = base64Decode(privateB64);
    _cachedPublicKeyBytes = base64Decode(publicB64);

    print('E2EE: Generated new key pair (first-time setup).');
    return publicB64;
  }

  Future<String?> getMyPublicKey() async {
    return _storage.read(key: _publicKeyStorageKey);
  }

  Future<String?> getMyPrivateKey() async {
    return _storage.read(key: _privateKeyStorageKey);
  }

  Future<String> encryptTextMessage({
    required String plainText,
    required String myUserId,
    required String peerUserId,
    required String peerPublicKeyB64,
  }) async {
    final secretKey = await _deriveConversationKey(
      myUserId: myUserId,
      peerUserId: peerUserId,
      peerPublicKeyB64: peerPublicKeyB64,
    );

    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plainText),
      secretKey: secretKey,
      nonce: nonce,
    );

    final payload = {
      'v': 1,
      'n': base64Encode(secretBox.nonce),
      'c': base64Encode(secretBox.cipherText),
      't': base64Encode(secretBox.mac.bytes),
    };

    final encoded = base64Encode(utf8.encode(jsonEncode(payload)));
    return 'e2e:v1:$encoded';
  }

  Future<String?> decryptTextMessage({
    required String encryptedPayload,
    required String myUserId,
    required String peerUserId,
    required String peerPublicKeyB64,
  }) async {
    if (!isE2EMessage(encryptedPayload)) return encryptedPayload;

    final payload = _parseEnvelope(encryptedPayload);
    if (payload == null) return null;

    final secretKey = await _deriveConversationKey(
      myUserId: myUserId,
      peerUserId: peerUserId,
      peerPublicKeyB64: peerPublicKeyB64,
    );

    final nonce = base64Decode(payload['n'] as String);
    final cipherText = base64Decode(payload['c'] as String);
    final tag = base64Decode(payload['t'] as String);

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: Mac(tag));
    final clearBytes = await _aesGcm.decrypt(secretBox, secretKey: secretKey);
    return utf8.decode(clearBytes);
  }

  bool isE2EMessage(String? value) {
    return value != null && value.startsWith('e2e:v1:');
  }

  Map<String, dynamic>? _parseEnvelope(String payload) {
    try {
      final encodedPart = payload.substring('e2e:v1:'.length);
      final decoded = utf8.decode(base64Decode(encodedPart));
      final map = jsonDecode(decoded);
      if (map is Map<String, dynamic> && map['v'] == 1) {
        return map;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<SecretKey> _deriveConversationKey({
    required String myUserId,
    required String peerUserId,
    required String peerPublicKeyB64,
  }) async {
    // Cache key: sorted pair so A→B and B→A share the same key
    final cacheKey = ([myUserId, peerUserId]..sort()).join(':');
    if (_conversationKeyCache.containsKey(cacheKey)) {
      return _conversationKeyCache[cacheKey]!;
    }

    // Use cached bytes if available, else read from Keystore (once)
    if (_cachedPrivateKeyBytes == null || _cachedPublicKeyBytes == null) {
      final myPrivateKeyB64 = await _storage.read(key: _privateKeyStorageKey);
      final myPublicKeyB64 = await _storage.read(key: _publicKeyStorageKey);
      if (myPrivateKeyB64 == null || myPublicKeyB64 == null) {
        throw StateError('E2EE identity key is missing.');
      }
      _cachedPrivateKeyBytes = base64Decode(myPrivateKeyB64);
      _cachedPublicKeyBytes = base64Decode(myPublicKeyB64);
    }

    final peerPublicBytes = base64Decode(peerPublicKeyB64);

    final myKeyPair = SimpleKeyPairData(
      _cachedPrivateKeyBytes!,
      publicKey: SimplePublicKey(_cachedPublicKeyBytes!, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: SimplePublicKey(peerPublicBytes, type: KeyPairType.x25519),
    );

    final participants = [myUserId, peerUserId]..sort();
    final nonce = utf8.encode(participants.join(':'));

    final derivedKey = await _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: nonce,
      info: utf8.encode(_protocolInfo),
    );

    _conversationKeyCache[cacheKey] = derivedKey;
    return derivedKey;
  }

  Future<void> _clearIdentity() async {
    await _storage.delete(key: _privateKeyStorageKey);
    await _storage.delete(key: _publicKeyStorageKey);
    await _storage.delete(key: _keyOwnerStorageKey);
    await _storage.delete(key: _backupKeyStorageKey);
  }
}
