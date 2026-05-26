import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/user_model.dart';
import '../config.dart';

/// Callback types for auth error and successful reconnect events.
typedef VoidCallback = void Function();
typedef AuthErrorCallback = void Function(String errorCode);

class SocketService {
  IO.Socket? _socket;
  bool _isConnected = false;

  /// Called when the socket emits a connection auth error (TOKEN_EXPIRED, Invalid Token).
  AuthErrorCallback? onAuthError;

  /// Called when the socket successfully reconnects after being disconnected.
  VoidCallback? onReconnected;

  IO.Socket get socket {
    if (_socket == null) {
      throw StateError('Socket not initialized. Call connect() first.');
    }
    return _socket!;
  }

  bool get isConnected => _isConnected;

  void connect(
    User user,
    VoidCallback onConnectionSuccess, {
    AuthErrorCallback? onAuthError,
    VoidCallback? onReconnected,
  }) {
    this.onAuthError = onAuthError;
    this.onReconnected = onReconnected;

    // Prevent duplicate connections
    if (_isConnected && _socket != null) {
      _socket!.disconnect();
    }

    final String socketUrl = AppConfig.baseUrl;

    _socket = IO.io(
      socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': user.token})
          .enableForceNew()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!.connect();

    _socket!.onConnect((_) {
      _isConnected = true;
      print('✅ Secure Socket Connected ($socketUrl)');
      onConnectionSuccess();
    });

    _socket!.onConnectError((data) {
      _isConnected = false;
      final message = data?.toString() ?? '';
      print('❌ Socket Connection Error: $message');

      // Propagate auth errors to the caller so they can attempt token refresh
      if (message.contains('TOKEN_EXPIRED')) {
        this.onAuthError?.call('TOKEN_EXPIRED');
      } else if (message.contains('Invalid Token') ||
          message.contains('Authentication error')) {
        this.onAuthError?.call('INVALID_TOKEN');
      }
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      print('❌ Socket Disconnected');
    });

    _socket!.onReconnect((_) {
      _isConnected = true;
      print('🔄 Socket Reconnected');
      this.onReconnected?.call();
    });
  }

  /// Update the auth token on the existing socket and reconnect.
  /// Called after a successful token refresh to restore the socket connection.
  void reconnectWithNewToken(String newToken) {
    if (_socket == null) return;
    _socket!.auth = {'token': newToken};
    if (!_isConnected) {
      _socket!.connect();
    }
  }

  void disconnect() {
    try {
      _isConnected = false;
      onAuthError = null;
      onReconnected = null;
      _socket?.disconnect();
      _socket?.dispose();
      _socket = null;
    } catch (e) {
      print('Socket Disconnect Warning: $e');
    }
  }
}
