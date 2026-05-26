import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config.dart';

// Global callback set by auth_provider to handle forced logout when refresh fails.
// Avoids circular dependency between api_client and auth_provider.
void Function()? onForceLogout;

/// Singleton Dio client with automatic token refresh.
/// All authenticated REST calls in auth_service.dart use this instance.
class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Prevents concurrent refresh attempts (only one refresh at a time).
  bool _isRefreshing = false;
  final List<_PendingRequest> _pendingQueue = [];

  ApiClient._internal() {
    dio = Dio(BaseOptions(
      baseUrl: AppConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
  }

  Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip auth header for public endpoints
    final publicPaths = ['/login', '/register', '/verify-otp',
        '/forgot-password', '/reset-password', '/refresh-token'];
    final isPublic = publicPaths.any((p) => options.path.endsWith(p));

    if (!isPublic) {
      final token = await _storage.read(key: 'jwt_token');
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  Future<void> _onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final response = err.response;
    if (response == null || response.statusCode != 401) {
      return handler.next(err);
    }

    // Check if this itself is the refresh call to avoid infinite loop
    if (err.requestOptions.path.contains('/refresh-token')) {
      _handleRefreshFailure();
      return handler.reject(err);
    }

    if (_isRefreshing) {
      // Queue this request and wait for the refresh to complete
      final completer = Completer<Response>();
      _pendingQueue.add(_PendingRequest(err.requestOptions, completer));
      try {
        final retryResponse = await completer.future;
        handler.resolve(retryResponse);
      } catch (e) {
        handler.reject(err);
      }
      return;
    }

    _isRefreshing = true;

    try {
      final newAccessToken = await _refreshAccessToken();
      if (newAccessToken == null) {
        _drainQueue(success: false);
        _handleRefreshFailure();
        return handler.reject(err);
      }

      // Retry the original request with the new token
      final retryResponse = await _retry(err.requestOptions, newAccessToken);
      _drainQueue(success: true, newToken: newAccessToken);
      handler.resolve(retryResponse);
    } catch (_) {
      _drainQueue(success: false);
      _handleRefreshFailure();
      handler.reject(err);
    } finally {
      _isRefreshing = false;
    }
  }

  /// Call /refresh-token, update secure storage, return new access token or null.
  Future<String?> _refreshAccessToken() async {
    try {
      final refreshToken = await _storage.read(key: 'refresh_token');
      if (refreshToken == null) return null;

      // Use a separate Dio instance to avoid triggering this interceptor again
      final refreshDio = Dio(BaseOptions(baseUrl: AppConfig.baseUrl));
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
    } catch (e) {
      print('Token refresh error: $e');
    }
    return null;
  }

  /// Retry a request with a new access token.
  Future<Response> _retry(RequestOptions options, String newToken) async {
    final retryOptions = Options(
      method: options.method,
      headers: {
        ...options.headers,
        'Authorization': 'Bearer $newToken',
      },
    );
    return dio.request(
      options.path,
      data: options.data,
      queryParameters: options.queryParameters,
      options: retryOptions,
    );
  }

  void _drainQueue({required bool success, String? newToken}) {
    for (final pending in _pendingQueue) {
      if (success && newToken != null) {
        _retry(pending.options, newToken)
            .then(pending.completer.complete)
            .catchError(pending.completer.completeError);
      } else {
        pending.completer.completeError(
          DioException(requestOptions: pending.options),
        );
      }
    }
    _pendingQueue.clear();
  }

  void _handleRefreshFailure() {
    print('⚠️ Token refresh failed — triggering forced logout');
    onForceLogout?.call();
  }
}

class _PendingRequest {
  final RequestOptions options;
  final Completer<Response> completer;
  _PendingRequest(this.options, this.completer);
}
