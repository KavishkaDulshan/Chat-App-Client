import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config.dart';
import '../models/contact_request.dart';

final contactServiceProvider = Provider<ContactService>((ref) => ContactService());

class ContactService {
  String get baseUrl => '${AppConfig.baseUrl}/contacts';
  final _storage = const FlutterSecureStorage();

  Future<String?> _token() => _storage.read(key: 'jwt_token');

  // Send a contact request via REST (socket also does this in real-time)
  Future<Map<String, dynamic>?> sendRequest(String toUserId) async {
    try {
      final token = await _token();
      if (token == null) return null;
      final resp = await http.post(
        Uri.parse('$baseUrl/request'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'toUserId': toUserId}),
      );
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> acceptRequest(String requestId) async {
    try {
      final token = await _token();
      if (token == null) return false;
      final resp = await http.post(
        Uri.parse('$baseUrl/accept/$requestId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> declineRequest(String requestId) async {
    try {
      final token = await _token();
      if (token == null) return false;
      final resp = await http.post(
        Uri.parse('$baseUrl/decline/$requestId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<ContactRequest>> getPendingRequests() async {
    try {
      final token = await _token();
      if (token == null) return [];
      final resp = await http.get(
        Uri.parse('$baseUrl/pending'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final list = jsonDecode(resp.body) as List;
        return list.map((e) => ContactRequest.fromJson(e)).toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<String> getContactStatus(String userId) async {
    try {
      final token = await _token();
      if (token == null) return 'none';
      final resp = await http.get(
        Uri.parse('$baseUrl/status/$userId'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['status']?.toString() ?? 'none';
      }
      return 'none';
    } catch (_) {
      return 'none';
    }
  }
}
