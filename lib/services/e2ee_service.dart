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

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final X25519 _x25519 = X25519();
  final AesGcm _aesGcm = AesGcm.with256bits();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final Random _random = Random.secure();

  Future<String> ensureIdentityKeyForUser(String userId) async {
    final ownerUserId = await _storage.read(key: _keyOwnerStorageKey);
    if (ownerUserId != null && ownerUserId != userId) {
      await _clearIdentity();
    }

    final existingPublicKey = await _storage.read(key: _publicKeyStorageKey);
    final existingPrivateKey = await _storage.read(key: _privateKeyStorageKey);

    if (existingPublicKey != null && existingPrivateKey != null) {
      await _storage.write(key: _keyOwnerStorageKey, value: userId);
      return existingPublicKey;
    }

    final keyPair = await _x25519.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final privateKeyBytes = await keyPair.extractPrivateKeyBytes();

    final publicB64 = base64Encode(publicKey.bytes);
    final privateB64 = base64Encode(privateKeyBytes);

    await _storage.write(key: _publicKeyStorageKey, value: publicB64);
    await _storage.write(key: _privateKeyStorageKey, value: privateB64);
    await _storage.write(key: _keyOwnerStorageKey, value: userId);

    return publicB64;
  }

  Future<String?> getMyPublicKey() async {
    return _storage.read(key: _publicKeyStorageKey);
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
    final myPrivateKeyB64 = await _storage.read(key: _privateKeyStorageKey);
    final myPublicKeyB64 = await _storage.read(key: _publicKeyStorageKey);

    if (myPrivateKeyB64 == null || myPublicKeyB64 == null) {
      throw StateError('E2EE identity key is missing.');
    }

    final myPrivateBytes = base64Decode(myPrivateKeyB64);
    final myPublicBytes = base64Decode(myPublicKeyB64);
    final peerPublicBytes = base64Decode(peerPublicKeyB64);

    final myKeyPair = SimpleKeyPairData(
      myPrivateBytes,
      publicKey: SimplePublicKey(myPublicBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: myKeyPair,
      remotePublicKey: SimplePublicKey(
        peerPublicBytes,
        type: KeyPairType.x25519,
      ),
    );

    final participants = [myUserId, peerUserId]..sort();
    final nonce = utf8.encode(participants.join(':'));

    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: nonce,
      info: utf8.encode(_protocolInfo),
    );
  }

  Future<void> _clearIdentity() async {
    await _storage.delete(key: _privateKeyStorageKey);
    await _storage.delete(key: _publicKeyStorageKey);
    await _storage.delete(key: _keyOwnerStorageKey);
  }
}
