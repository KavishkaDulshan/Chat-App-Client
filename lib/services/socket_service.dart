import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/user_model.dart';

class SocketService {
  late IO.Socket _socket;

  IO.Socket get socket => _socket;

  // Initialize and Connect
  void connect(User user, Function onConnectionSuccess) {
    // NOTE: Use 'http://10.0.2.2:3000' for Android Emulator
    _socket = IO.io('http://localhost:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    _socket.connect();

    _socket.onConnect((_) {
      print('✅ Socket Connected');
      // Handshake: Identify ourselves to the server
      _socket.emit('login', user.username);
    });

    // Wait for server to confirm we are logged in
    _socket.on('login_success', (_) {
      print('✅ Handshake Complete');
      onConnectionSuccess();
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
