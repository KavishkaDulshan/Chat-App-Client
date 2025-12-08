import 'package:flutter/material.dart';
// ignore: library_prefixes
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  runApp(const MaterialApp(home: ChatScreen()));
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late IO.Socket socket;
  final TextEditingController _controller = TextEditingController();
  final List<String> _messages = []; // Stores our chat history locally

  @override
  void initState() {
    super.initState();
    connectToServer();
  }

  void connectToServer() {
    // 1. Connection Logic
    // IF TESTING ON ANDROID EMULATOR: Use 'http://10.0.2.2:3000'
    // IF TESTING ON WINDOWS/WEB: Use 'http://localhost:3000'
    socket = IO.io('http://localhost:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.connect();

    // 2. Listen for Connection Success
    socket.onConnect((_) {
      print('✅ Connected to Backend');
    });

    // 3. Listen for Incoming Messages
    socket.on('chat_message', (data) {
      print('📩 Received: $data');
      setState(() {
        _messages.add(data);
      });
    });

    // 4. Handle Disconnect
    socket.onDisconnect((_) => print('❌ Disconnected'));
  }

  void sendMessage() {
    if (_controller.text.isNotEmpty) {
      // Emit the message to the server
      socket.emit('chat_message', _controller.text);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Dev Chat")),
      body: Column(
        children: [
          // Message List
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return ListTile(
                  title: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue[100],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(_messages[index]),
                    ),
                  ),
                );
              },
            ),
          ),
          // Input Field
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      labelText: "Type a message...",
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
