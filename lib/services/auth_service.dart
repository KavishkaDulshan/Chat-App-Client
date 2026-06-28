import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../models/user_model.dart';
import '../config.dart';
import 'api_client.dart';

final authServiceProvider = Provider((ref) => AuthService());

class AuthService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Use the shared Dio client (has the auto-refresh interceptor).
  Dio get _dio => ApiClient().dio;

  String get baseUrl => AppConfig.baseUrl;

  // ─── LOGIN ──────────────────────────────────────────────────────────────────
  Future<User?> login(String email, String password) async {
    try {
      final response = await _dio.post('/login', data: {
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final token = data['token'] as String;
        final refreshToken = data['refreshToken'] as String?;
        final userJson = data['user'] as Map<String, dynamic>;

        await _storage.write(key: 'jwt_token', value: token);
        if (refreshToken != null) {
          await _storage.write(key: 'refresh_token', value: refreshToken);
        }
        await _storage.write(key: 'user_data', value: jsonEncode(userJson));

        _syncFcmToken();
        return User.fromJson(userJson, token);
      }
    } on DioException catch (e) {
      print('Login Error: ${e.response?.data ?? e.message}');
    } catch (e) {
      print('Login Error: $e');
    }
    return null;
  }

  // ─── REGISTER ───────────────────────────────────────────────────────────────
  Future<bool> register(String username, String email, String password) async {
    try {
      final response = await _dio.post('/register', data: {
        'username': username,
        'email': email,
        'password': password,
      });
      return response.statusCode == 201;
    } catch (e) {
      print('Register Error: $e');
      return false;
    }
  }

  // ─── VERIFY OTP ─────────────────────────────────────────────────────────────
  Future<User?> verifyOTP(String email, String otp) async {
    try {
      final response = await _dio.post('/verify-otp', data: {
        'email': email,
        'otp': otp,
      });

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final token = data['token'] as String;
        final refreshToken = data['refreshToken'] as String?;
        final userJson = data['user'] as Map<String, dynamic>;

        await _storage.write(key: 'jwt_token', value: token);
        if (refreshToken != null) {
          await _storage.write(key: 'refresh_token', value: refreshToken);
        }
        await _storage.write(key: 'user_data', value: jsonEncode(userJson));

        _syncFcmToken();
        return User.fromJson(userJson, token);
      }
    } on DioException catch (e) {
      print('Verification Error: ${e.response?.data ?? e.message}');
    } catch (e) {
      print('Verification Error: $e');
    }
    return null;
  }

  // ─── AUTO LOGIN ─────────────────────────────────────────────────────────────
  Future<User?> tryAutoLogin() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final userData = await _storage.read(key: 'user_data');
      final refreshToken = await _storage.read(key: 'refresh_token');

      if (token != null && userData != null) {
        // Check if access token appears expired (basic exp decode without verify)
        if (_isTokenLikelyExpired(token) && refreshToken != null) {
          try {
            // Silently attempt refresh before returning user
            final newToken = await _silentRefresh(refreshToken);
            if (newToken != null) {
              _syncFcmToken();
              return User.fromJson(jsonDecode(userData), newToken);
            }
            // Refresh returned null (explicitly invalid token) — clear all credentials
            await logout();
            return null;
          } on NetworkException catch (e) {
            print('Auto Login: Offline/Network issue during token refresh ($e). Returning cached user.');
            // Allow offline mode by returning the cached user with the existing (expired) token
            return User.fromJson(jsonDecode(userData), token);
          }
        }

        _syncFcmToken();
        return User.fromJson(jsonDecode(userData), token);
      }
    } catch (e) {
      print('Auto Login Error: $e');
    }
    return null;
  }

  /// Silently refresh and return new access token, or null on failure.
  Future<String?> _silentRefresh(String refreshToken) async {
    try {
      final refreshDio = Dio(BaseOptions(baseUrl: baseUrl));
      final response = await refreshDio.post('/refresh-token', data: {
        'refreshToken': refreshToken,
      });
      if (response.statusCode == 200) {
        final newAccessToken = response.data['token'] as String?;
        final newRefreshToken = response.data['refreshToken'] as String?;
        if (newAccessToken != null) {
          await _storage.write(key: 'jwt_token', value: newAccessToken);
        }
        if (newRefreshToken != null) {
          await _storage.write(key: 'refresh_token', value: newRefreshToken);
        }
        return newAccessToken;
      }
    } on DioException catch (e) {
      print('Silent refresh error: $e');
      if (e.type != DioExceptionType.badResponse) {
        throw NetworkException('Network connection failed: ${e.message}');
      }
      final status = e.response?.statusCode;
      if (status != null && status != 400 && status != 401 && status != 403) {
        throw NetworkException('Server side error during refresh: $status');
      }
    } catch (e) {
      print('Silent refresh error: $e');
      throw NetworkException('Unknown error during refresh: $e');
    }
    return null;
  }

  /// Lightweight expiry check by decoding JWT payload (no verification).
  bool _isTokenLikelyExpired(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return true;
      // Base64url decode the payload
      final payload = parts[1];
      final normalized = base64Url.normalize(payload);
      final decoded = jsonDecode(utf8.decode(base64Url.decode(normalized)));
      final exp = decoded['exp'] as int?;
      if (exp == null) return false;
      // Consider expired if less than 60 seconds remain
      return DateTime.fromMillisecondsSinceEpoch(exp * 1000)
          .isBefore(DateTime.now().add(const Duration(seconds: 60)));
    } catch (_) {
      return false;
    }
  }

  // ─── LOGOUT ─────────────────────────────────────────────────────────────────
  Future<void> logout() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      // Tell server to invalidate this device's refresh token
      await _dio.post('/logout', data: {'refreshToken': refreshToken ?? ''});
    } catch (e) {
      print('Server logout error (non-fatal): $e');
    }
    await _storage.delete(key: 'jwt_token');
    await _storage.delete(key: 'refresh_token');
    await _storage.delete(key: 'user_data');
  }

  // ─── SEARCH USER ────────────────────────────────────────────────────────────
  Future<List<dynamic>> searchUser(String query) async {
    try {
      final response = await _dio.get('/search', queryParameters: {'username': query});
      if (response.statusCode == 200) {
        final data = response.data;
        // Guard against nginx returning HTML (SPA fallback) instead of JSON
        if (data is List) return data;
        if (data is String && data.trim().startsWith('<')) {
          print('Search: server returned HTML — nginx misconfiguration: '
              'GET /search is served as a static file, not proxied to the API.');
          return [];
        }
        print('Search: unexpected response type: ${data.runtimeType}');
      } else {
        print('Search Error: status ${response.statusCode}');
      }
    } on DioException catch (e) {
      print('Search DioError: ${e.response?.statusCode} - ${e.response?.data ?? e.message}');
    } catch (e) {
      print('Search Error: $e');
    }
    return [];
  }

  // ─── GET CONVERSATIONS ──────────────────────────────────────────────────────
  Future<List<dynamic>> getConversations() async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final userData = await _storage.read(key: 'user_data');
      if (token == null || userData == null) return [];

      final user = User.fromJson(jsonDecode(userData), token);
      final response = await _dio.get('/chat/conversations/${user.id}');

      if (response.statusCode == 200) {
        return response.data as List<dynamic>;
      } else {
        print('Get Chat Failed: ${response.statusCode}');
      }
    } catch (e) {
      print('Get Conversations Error: $e');
    }
    return [];
  }

  // ─── FCM TOKEN SYNC ─────────────────────────────────────────────────────────
  Future<void> _syncFcmToken() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await _dio.post('/fcm-token', data: {'token': fcmToken});
      }
    } catch (e) {
      print('FCM Sync Error: $e');
    }
  }

  // ─── E2EE KEY MANAGEMENT ────────────────────────────────────────────────────
  Future<bool> uploadE2EEPublicKey(
    String publicKey, {
    String? privateKey,
    String? backupKey,
    int keyVersion = 1,
  }) async {
    try {
      final body = <String, dynamic>{
        'publicKey': publicKey,
        'keyVersion': keyVersion,
      };
      if (privateKey != null && privateKey.isNotEmpty) body['privateKey'] = privateKey;
      if (backupKey != null && backupKey.isNotEmpty) body['backupKey'] = backupKey;

      final response = await _dio.put('/e2e-key', data: body);
      return response.statusCode == 200;
    } catch (e) {
      print('Upload E2EE Key Error: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> fetchMyE2EEKeyPair() async {
    try {
      final response = await _dio.get('/my-e2e-keys');
      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        final pub = data['e2e_public_key'];
        final priv = data['e2e_private_key'];
        if (pub is String && pub.isNotEmpty && priv is String && priv.isNotEmpty) {
          return data;
        }
        return null;
      } else if (response.statusCode == 404) {
        return null;
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<String?> getUserE2EEPublicKey(String userId) async {
    try {
      final response = await _dio.get('/users/$userId/e2e-key');
      if (response.statusCode != 200) return null;
      final data = response.data as Map<String, dynamic>;
      final key = data['e2e_public_key'];
      return (key is String && key.isNotEmpty) ? key : null;
    } catch (e) {
      print('Fetch Peer E2EE Key Error: $e');
      return null;
    }
  }

  /// Upload user's Recovery PIN to enable PIN-based E2EE key recovery.
  Future<bool> setRecoveryPin(String pin) async {
    try {
      final response = await _dio.post('/e2e-pin-backup', data: {'pin': pin});
      return response.statusCode == 200;
    } catch (e) {
      print('Set Recovery PIN Error: $e');
      return false;
    }
  }

  // ─── PROFILE ────────────────────────────────────────────────────────────────
  Future<User?> updateProfile({
    String? imageUrl,
    String? username,
    bool? showNotificationPreview,
  }) async {
    try {
      final token = await _storage.read(key: 'jwt_token');
      final body = <String, dynamic>{};
      if (imageUrl != null) body['profile_pic'] = imageUrl;
      if (username != null) body['username'] = username;
      if (showNotificationPreview != null) {
        body['showNotificationPreview'] = showNotificationPreview;
      }

      final response = await _dio.put('/update-profile', data: body);

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        await _storage.write(key: 'user_data', value: jsonEncode(data));
        return User.fromJson(data, token!);
      }
    } catch (e) {
      print('Update Profile Error: $e');
    }
    return null;
  }

  Future<String?> forgotPassword(String email) async {
    try {
      final response = await _dio.post('/forgot-password', data: {'email': email});
      if (response.statusCode == 200) return null; // success
      final data = response.data as Map<String, dynamic>;
      return data['error'] ?? 'Failed to send OTP';
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map) return data['error'] ?? 'Failed to send OTP';
      return 'Network error. Please check your connection.';
    } catch (e) {
      return 'Network error. Please check your connection.';
    }
  }

  Future<bool> resetPassword(String email, String otp, String newPassword) async {
    try {
      final response = await _dio.post('/reset-password', data: {
        'email': email,
        'otp': otp,
        'newPassword': newPassword,
      });
      return response.statusCode == 200;
    } catch (e) {
      print('Reset Password Error: $e');
      return false;
    }
  }
}
