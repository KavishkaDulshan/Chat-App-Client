import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/user_model.dart';
import '../config.dart';

class SocketService {
  IO.Socket? _socket;
  bool _isConnected = false;

  IO.Socket get socket {
    if (_socket == null) {
      throw StateError('Socket not initialized. Call connect() first.');
    }
    return _socket!;
  }

  bool get isConnected => _isConnected;

  void connect(User user, Function onConnectionSuccess) {
    // Prevent duplicate connections
    if (_isConnected && _socket != null) {
      _socket!.disconnect();
    }

    // DYNAMIC URL
    String socketUrl = AppConfig.baseUrl;

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
      print('❌ Socket Connection Error: $data');
    });

    _socket!.onDisconnect((_) {
      _isConnected = false;
      print('❌ Socket Disconnected');
    });

    _socket!.onReconnect((_) {
      _isConnected = true;
      print('🔄 Socket Reconnected');
    });
  }

  void disconnect() {
    try {
      _isConnected = false;
      _socket?.disconnect();
      _socket?.dispose();
      _socket = null;
    } catch (e) {
      print('Socket Disconnect Warning: $e');
    }
  }
}
