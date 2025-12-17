import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/user_model.dart';

class SocketService {
  late IO.Socket _socket;

  IO.Socket get socket => _socket;

  // Initialize and Connect Securely
  void connect(User user, Function onConnectionSuccess) {
    // 1. Dispose if already connected to avoid duplicates
    try {
      _socket.dispose();
    } catch (e) {
      // ignore
    }

    // 2. Connect with JWT TOKEN
    // NOTE: Use 'http://10.0.2.2:3000' for Android Emulator
    _socket = IO.io(
      'http://localhost:3000',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': user.token}) // <--- SEND TOKEN HERE
          .enableForceNew()
          .build(),
    );

    _socket.connect();

    // 3. Listen for Success
    _socket.onConnect((_) {
      print('✅ Secure Socket Connected');

      // We don't need to emit 'login' anymore!
      // The handshake verified us. We are ready immediately.
      onConnectionSuccess();
    });

    _socket.onConnectError((data) {
      print('❌ Socket Connection Error: $data');
    });

    _socket.onDisconnect((_) => print('❌ Socket Disconnected'));
  }

  void disconnect() {
    try {
      _socket.disconnect();
    } catch (e) {
      print(e);
    }
  }
}
