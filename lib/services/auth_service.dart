import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../config.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // <--- NEW IMPORT

final authServiceProvider = Provider((ref) => AuthService());

class AuthService {
  String get baseUrl => AppConfig.baseUrl;
  final storage = const FlutterSecureStorage();

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

        // 1. SAVE TOKEN & USER DATA
        await storage.write(key: 'jwt_token', value: token);
        await storage.write(key: 'user_data', value: jsonEncode(userJson));
        await _syncFcmToken();

        return User.fromJson(userJson, token);
      } else {
        print('Login Failed: ${response.body}');
      }
    } catch (e) {
      print('Login Error: $e');
    }
    return null;
  }

  // === RESTORE SESSION ===
  Future<User?> tryAutoLogin() async {
    try {
      final token = await storage.read(key: 'jwt_token');
      final userStr = await storage.read(key: 'user_data');

      if (token != null && userStr != null) {
        _syncFcmToken();
        final userJson = jsonDecode(userStr);
        return User.fromJson(userJson, token);
      }
    } catch (e) {
      print("Auto Login Error: $e");
    }
    return null;
  }

  Future<void> _syncFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await sendFcmToken(token);
      }
    } catch (e) {
      print("FCM Sync Error: $e");
    }
  }

  // === LOGOUT ===
  Future<void> logout() async {
    await storage.deleteAll();
  }

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
      return false;
    }
  }

  // lib/services/auth_service.dart

  Future<Map<String, dynamic>?> searchUser(String username) async {
    try {
      // 1. Get the Token
      final token = await storage.read(key: 'jwt_token');

      if (token == null) {
        print("⚠️ Search failed: No User Token found");
        return null;
      }

      // 2. Send Request WITH Headers
      final response = await http.get(
        Uri.parse('$baseUrl/search?username=$username'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token', // <--- THIS WAS MISSING
        },
      );

      // 3. Handle Response
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        // Debug Log: Use this to see if it's 401 (Auth) or 404 (Not Found)
        print(
          "❌ Search Failed: Status ${response.statusCode} - ${response.body}",
        );
      }
    } catch (e) {
      print("❌ Search Error: $e");
    }
    return null;
  }

  Future<List<dynamic>> getConversations(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/conversations/$userId'),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (e) {}
    return [];
  }

  Future<void> sendFcmToken(String token) async {
    try {
      final jwtToken = await storage.read(key: 'jwt_token');
      if (jwtToken == null) return;

      final response = await http.post(
        Uri.parse('$baseUrl/fcm-token'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $jwtToken',
        },
        body: jsonEncode({'token': token}),
      );

      if (response.statusCode == 200) {
        print("✅ FCM Token sent to server");
      }
    } catch (e) {
      print("❌ Failed to send FCM token: $e");
    }
  }
}
