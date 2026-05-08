import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../config.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

final authServiceProvider = Provider((ref) => AuthService());

class AuthService {
  String get baseUrl => AppConfig.baseUrl;
  final storage = const FlutterSecureStorage();

  // --- LOGIN ---
  Future<User?> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'];
        final userJson = data['user'];

        await storage.write(key: 'jwt_token', value: token);
        await storage.write(key: 'user_data', value: jsonEncode(userJson));

        _syncFcmToken(); // Sync token on login

        return User.fromJson(userJson, token);
      }
    } catch (e) {
      print("Login Error: $e");
    }
    return null;
  }

  // --- REGISTER ---
  Future<bool> register(String username, String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'email': email,
          'password': password,
        }),
      );
      return response.statusCode == 201;
    } catch (e) {
      print("Register Error: $e");
      return false;
    }
  }

  // --- VERIFY OTP ---
  Future<User?> verifyOTP(String email, String otp) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/verify-otp'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'otp': otp}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'];
        final userJson = data['user'];

        await storage.write(key: 'jwt_token', value: token);
        await storage.write(key: 'user_data', value: jsonEncode(userJson));

        _syncFcmToken();

        return User.fromJson(userJson, token);
      }
    } catch (e) {
      print("Verification Error: $e");
    }
    return null;
  }

  // --- SEARCH USER ---
  Future<List<dynamic>> searchUser(String query) async {
    try {
      final token = await storage.read(key: 'jwt_token');
      if (token == null) return [];

      final response = await http.get(
        Uri.parse('$baseUrl/search?username=$query'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) return data;
        return [];
      }
    } catch (e) {
      print("Search Error: $e");
    }
    return [];
  }

  // --- NEW: GET CONVERSATIONS (Fixes "Tap to chat") ---
  Future<List<dynamic>> getConversations() async {
    try {
      final token = await storage.read(key: 'jwt_token');
      final userData = await storage.read(key: 'user_data');
      if (token == null || userData == null) return [];

      final user = User.fromJson(jsonDecode(userData), token);

      // Note: Make sure your backend has app.use('/api/chat', chatRoutes)
      final response = await http.get(
        Uri.parse('$baseUrl/chat/conversations/${user.id}'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print("Get Chat Failed: ${response.statusCode} - ${response.body}");
      }
    } catch (e) {
      print("Get Conversations Error: $e");
    }
    return [];
  }

  // --- AUTO LOGIN ---
  Future<User?> tryAutoLogin() async {
    try {
      final token = await storage.read(key: 'jwt_token');
      final userData = await storage.read(key: 'user_data');

      if (token != null && userData != null) {
        _syncFcmToken(); // Sync on auto-login
        return User.fromJson(jsonDecode(userData), token);
      }
    } catch (e) {
      print("Auto Login Error: $e");
    }
    return null;
  }

  // --- LOGOUT ---
  Future<void> logout() async {
    await storage.delete(key: 'jwt_token');
    await storage.delete(key: 'user_data');
  }

  // --- FCM TOKEN SYNC (Android only) ---
  Future<void> _syncFcmToken() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await _sendFcmTokenToServer(fcmToken);
      }
    } catch (e) {
      print("FCM Sync Error: $e");
    }
  }

  Future<void> _sendFcmTokenToServer(String token) async {
    try {
      final jwtToken = await storage.read(key: 'jwt_token');
      if (jwtToken == null) return;

      await http.post(
        Uri.parse('$baseUrl/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({'token': token}),
      );
    } catch (e) {
      print("Failed to send FCM token: $e");
    }
  }

  Future<bool> uploadE2EEPublicKey(
    String publicKey, {
    String? privateKey,
    String? backupKey,
    int keyVersion = 1,
  }) async {
    try {
      final jwtToken = await storage.read(key: 'jwt_token');
      if (jwtToken == null) return false;

      final body = <String, dynamic>{
        'publicKey': publicKey,
        'keyVersion': keyVersion,
      };
      if (privateKey != null && privateKey.isNotEmpty) {
        body['privateKey'] = privateKey;
      }
      if (backupKey != null && backupKey.isNotEmpty) {
        body['backupKey'] = backupKey;
      }

      final response = await http.put(
        Uri.parse('$baseUrl/e2e-key'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode(body),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Upload E2EE Key Error: $e');
      return false;
    }
  }

  /// Fetch the authenticated user's own E2E key pair from the server.
  /// Returns {e2e_public_key, e2e_private_key, e2e_key_version} or null.
  Future<Map<String, dynamic>?> fetchMyE2EEKeyPair() async {
    try {
      final jwtToken = await storage.read(key: 'jwt_token');
      if (jwtToken == null) return null;

      final response = await http.get(
        Uri.parse('$baseUrl/my-e2e-keys'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final pub = data['e2e_public_key'];
      final priv = data['e2e_private_key'];

      if (pub is String && pub.isNotEmpty && priv is String && priv.isNotEmpty) {
        return data;
      }
      return null;
    } catch (e) {
      print('Fetch My E2EE Keys Error: $e');
      return null;
    }
  }

  Future<String?> getUserE2EEPublicKey(String userId) async {
    try {
      final jwtToken = await storage.read(key: 'jwt_token');
      if (jwtToken == null) return null;

      final response = await http.get(
        Uri.parse('$baseUrl/users/$userId/e2e-key'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
      );

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final key = data['e2e_public_key'];
      if (key is String && key.isNotEmpty) {
        return key;
      }
      return null;
    } catch (e) {
      print('Fetch Peer E2EE Key Error: $e');
      return null;
    }
  }

  Future<User?> updateProfile({String? imageUrl, String? username, bool? showNotificationPreview}) async {
    try {
      final token = await storage.read(key: 'jwt_token');

      final body = <String, dynamic>{};
      if (imageUrl != null) body['profile_pic'] = imageUrl;
      if (username != null) body['username'] = username;
      if (showNotificationPreview != null) body['showNotificationPreview'] = showNotificationPreview;

      print("📤 updateProfile request: $body to $baseUrl/update-profile");

      final response = await http.put(
        Uri.parse('$baseUrl/update-profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      print("📥 updateProfile response: ${response.statusCode} ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Update local storage with new user data
        await storage.write(key: 'user_data', value: jsonEncode(data));
        return User.fromJson(data, token!);
      } else {
        print("❌ updateProfile failed: ${response.statusCode}");
      }
    } catch (e) {
      print("Update Profile Error: $e");
    }
    return null;
  }

  Future<String?> forgotPassword(String email) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/forgot-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      if (response.statusCode == 200) {
        return null; // success
      }
      final data = jsonDecode(response.body);
      return data['error'] ?? 'Failed to send OTP';
    } catch (e) {
      print("Forgot Password Error: $e");
      return 'Network error. Please check your connection.';
    }
  }

  Future<bool> resetPassword(String email, String otp, String newPassword) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': email,
          'otp': otp,
          'newPassword': newPassword,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Reset Password Error: $e");
      return false;
    }
  }
}
