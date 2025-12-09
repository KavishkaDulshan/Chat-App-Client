import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: LoginScreen()),
  );
}

// -----------------------------------
// SCREEN 1: THE LOGIN PAGE
// -----------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  late IO.Socket socket;
  bool _isLoading = false;

  void connectAndLogin() {
    if (_usernameController.text.isEmpty) return;

    setState(() => _isLoading = true);

    // 1. Initialize Socket
    // NOTE: Use 'http://10.0.2.2:3000' for Android Emulator
    // NOTE: Use 'http://localhost:3000' for Windows Desktop
    socket = IO.io('http://localhost:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    socket.connect();

    // 2. Listen for connection
    socket.onConnect((_) {
      print('✅ Connected to Server');
      // 3. Emit the 'login' event we wrote in Node.js
      socket.emit('login', _usernameController.text.trim());
    });

    // 4. Listen for 'login_success' from Server
    socket.on('login_success', (userData) {
      print('🔓 Login Success: $userData');
      setState(() => _isLoading = false);

      // Navigate to Chat Screen and pass the socket & user data
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => UserListScreen(
            // <--- CHANGED THIS
            socket: socket,
            currentUser: userData,
          ),
        ),
      );
    });

    // Handle errors (optional but good practice)
    socket.onDisconnect((_) {
      setState(() => _isLoading = false);
      print('❌ Disconnected');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Join Chat")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: "Enter your nickname",
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: connectAndLogin,
                    child: const Text("Enter Chat Room"),
                  ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------
// SCREEN 2: THE CHAT ROOM
// -----------------------------------
class ChatScreen extends StatefulWidget {
  final IO.Socket socket;
  final String username;
  final String userId;

  const ChatScreen({
    super.key,
    required this.socket,
    required this.username,
    required this.userId,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];

  @override
  void initState() {
    super.initState();
    setupSocketListeners();
  }

  void setupSocketListeners() {
    // 1. Listen for incoming new messages
    widget.socket.on('chat_message', (data) {
      if (mounted) {
        setState(() {
          _messages.add(data);
        });
      }
    });

    // 2. Listen for HISTORY load (New)
    widget.socket.on('history_load', (data) {
      // The data comes as a List of Maps. We need to cast it.
      if (mounted) {
        setState(() {
          // Clear current list just in case
          _messages.clear();
          // Add all historical messages
          for (var msg in data) {
            _messages.add(msg);
          }
        });
        print("📜 History Loaded: ${_messages.length} messages");
      }
    });
  }

  void sendMessage() {
    if (_messageController.text.isNotEmpty) {
      // We will implement the proper "Save to DB" logic next.
      // For now, we just send the text.
      Map<String, dynamic> msgData = {
        'content': _messageController.text,
        'sender_id': widget.userId,
        'sender_name': widget.username, // Temporary for UI
        'type': 'text',
      };

      widget.socket.emit('chat_message', msgData);
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Chat as ${widget.username}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              widget.socket.disconnect();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['sender_id'] == widget.userId;

                return Align(
                  alignment: isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      vertical: 5,
                      horizontal: 10,
                    ),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isMe ? Colors.blue : Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg['sender_name'] ?? 'Unknown',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isMe ? Colors.white70 : Colors.black54,
                          ),
                        ),
                        Text(
                          msg['content'] ?? '',
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: "Type a message...",
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

class UserListScreen extends StatefulWidget {
  final IO.Socket socket;
  final Map<String, dynamic> currentUser;

  const UserListScreen({
    super.key,
    required this.socket,
    required this.currentUser,
  });

  @override
  _UserListScreenState createState() => _UserListScreenState();
}

class _UserListScreenState extends State<UserListScreen> {
  List<dynamic> _users = [];

  @override
  void initState() {
    super.initState();
    // 1. Ask server for the list
    widget.socket.emit('get_users');

    // 2. Listen for the list response
    widget.socket.on('users_list', (data) {
      if (mounted) setState(() => _users = data);
    });

    // 3. Listen for real-time status updates (Online/Offline)
    widget.socket.on('user_status_change', (data) {
      if (mounted) {
        setState(() {
          // Find the user in our list and update their status
          final index = _users.indexWhere((u) => u['_id'] == data['userId']);
          if (index != -1) {
            _users[index]['is_online'] = data['isOnline'];
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Contacts"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Navigator.of(context).pop(), // Simple logout
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          final isOnline = user['is_online'] ?? false;

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: isOnline ? Colors.green : Colors.grey,
              child: const Icon(Icons.person, color: Colors.white),
            ),
            title: Text(user['username']),
            subtitle: Text(isOnline ? "Online" : "Offline"),
            onTap: () {
              // FOR NOW: We still just open the Global Chat.
              // NEXT STEP: We will pass 'user["_id"]' to open a private room.
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    socket: widget.socket,
                    username: widget.currentUser['username'],
                    userId: widget.currentUser['_id'],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
