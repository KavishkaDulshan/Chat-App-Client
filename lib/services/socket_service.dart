import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../models/user_model.dart';
import '../config.dart';

class SocketService {
  late IO.Socket _socket;

  IO.Socket get socket => _socket;

  void connect(User user, Function onConnectionSuccess) {
    // DYNAMIC URL
    String socketUrl = AppConfig.baseUrl;

    _socket = IO.io(
      socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': user.token})
          .enableForceNew()
          .build(),
    );

    _socket.connect();

    _socket.onConnect((_) {
      print('✅ Secure Socket Connected ($socketUrl)');
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
    } catch (e) {}
  }
}
