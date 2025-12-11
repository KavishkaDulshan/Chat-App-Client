import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  // Use localhost for Windows. If using Android Emulator, use 'http://10.0.2.2:3000'
  final String baseUrl = 'http://localhost:3000';
  final storage = const FlutterSecureStorage();

  // --- LOGIN ---
  Future<Map<String, dynamic>?> login(String email, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'password': password}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Save token securely
        await storage.write(key: 'jwt_token', value: data['token']);
        return data['user']; // Return the user info
      } else {
        print('Login Failed: ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error: $e');
      return null;
    }
  }

  // --- SIGN UP ---
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

      if (response.statusCode == 201) {
        return true;
      } else {
        print('Registration Failed: ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error: $e');
      return false;
    }
  }

  // --- LOGOUT ---
  Future<void> logout() async {
    await storage.delete(key: 'jwt_token');
  }
}
