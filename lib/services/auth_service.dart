import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';

// Riverpod Provider for AuthService
final authServiceProvider = Provider((ref) => AuthService());

class AuthService {
  // Use localhost for Windows. If using Android Emulator, use 'http://10.0.2.2:3000'
  final String baseUrl = 'http://localhost:3000';
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

        // Return User Object
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
      print('Register Error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    await storage.delete(key: 'jwt_token');
  }

  // ... existing code ...

  // --- SEARCH USER ---
  Future<Map<String, dynamic>?> searchUser(String username) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/search?username=$username'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Search Error: $e');
    }
    return null;
  }

  // --- GET INBOX ---
  Future<List<dynamic>> getConversations(String myUserId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/conversations/$myUserId'),
      );
      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (e) {
      print('Inbox Error: $e');
    }
    return [];
  }
}
