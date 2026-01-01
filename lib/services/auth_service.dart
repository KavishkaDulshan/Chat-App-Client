import 'dart:convert';
import 'dart:io'; // Required for Platform check
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';

final authServiceProvider = Provider((ref) => AuthService());

class AuthService {
  // DYNAMIC URL LOGIC
  // Returns localhost for Windows, 10.0.2.2 for Android Emulator
  String get baseUrl {
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

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
        // Save token securely
        await storage.write(key: 'jwt_token', value: token);
        return User.fromJson(data['user'], token);
      } else {
        print('Login Failed: ${response.body}');
      }
    } catch (e) {
      print('Login Error: $e');
    }
    return null;
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

  // --- THIS WAS MISSING ---
  Future<void> logout() async {
    await storage.delete(key: 'jwt_token');
  }
}
