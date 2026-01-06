import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';
import '../config.dart';

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
        final userJson = data['user']; // The user object from backend

        // 1. SAVE TOKEN & USER DATA
        await storage.write(key: 'jwt_token', value: token);
        await storage.write(key: 'user_data', value: jsonEncode(userJson));

        return User.fromJson(userJson, token);
      } else {
        print('Login Failed: ${response.body}');
      }
    } catch (e) {
      print('Login Error: $e');
    }
    return null;
  }

  // === NEW: RESTORE SESSION ===
  Future<User?> tryAutoLogin() async {
    try {
      final token = await storage.read(key: 'jwt_token');
      final userStr = await storage.read(key: 'user_data');

      if (token != null && userStr != null) {
        final userJson = jsonDecode(userStr);
        return User.fromJson(userJson, token);
      }
    } catch (e) {
      print("Auto Login Error: $e");
    }
    return null;
  }

  // === NEW: LOGOUT ===
  Future<void> logout() async {
    await storage.deleteAll();
  }

  // ... (Keep register, searchUser, getConversations as they are) ...
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

  Future<Map<String, dynamic>?> searchUser(String username) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/search?username=$username'),
      );
      if (response.statusCode == 200) return jsonDecode(response.body);
    } catch (e) {}
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
}
