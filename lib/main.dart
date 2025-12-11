import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';
import 'package:intl/intl.dart';
import 'auth_service.dart';

// Configuration
// Use 'http://10.0.2.2:3000' for Android Emulator
// Use 'http://localhost:3000' for iOS Simulator or Windows Desktop
const String kServerUrl = 'http://localhost:3000';

void main() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: LoginScreen()),
  );
}

// -----------------------------------

// SCREEN 1: THE AUTH SCREEN (Login & Signup)

// -----------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();

  // Text Controllers
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _usernameController =
      TextEditingController(); // Only for signup

  bool _isLoginMode = true; // Toggle between Login and Signup
  bool _isLoading = false;
  late IO.Socket socket;

  void handleAuth() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final username = _usernameController.text.trim();

    if (email.isEmpty || password.isEmpty) return;
    if (!_isLoginMode && username.isEmpty) return;

    setState(() => _isLoading = true);

    if (_isLoginMode) {
      // --- LOGIN FLOW ---
      final user = await _authService.login(email, password);

      if (user != null) {
        // Login success! Now connect the socket.
        connectSocket(user);
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Login Failed. Check credentials.")),
        );
      }
    } else {
      // --- SIGNUP FLOW ---
      final success = await _authService.register(username, email, password);
      if (success) {
        // If signup works, switch to login mode automatically
        setState(() {
          _isLoginMode = true;
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Account Created! Please Login.")),
        );
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Signup Failed. Email/User might exist."),
          ),
        );
      }
    }
  }

  void connectSocket(Map<String, dynamic> user) {
    // 1. Initialize Socket
    socket = IO.io('http://localhost:3000', <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      // OPTIONAL: We can pass the token here for extra security later
      // 'auth': {'token': await _authService.storage.read(key: 'jwt_token')}
    });

    socket.connect();

    socket.onConnect((_) {
      print('✅ Socket Connected');

      // We still need to tell the socket WHO we are for the "Online Status" list
      // We use the ID returned from the REST API
      socket.emit('login', user['username']);
    });

    socket.on('login_success', (_) {
      setState(() => _isLoading = false);

      // Navigate to Contacts
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) =>
              UserListScreen(socket: socket, currentUser: user),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isLoginMode ? "Login" : "Create Account")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // USERNAME (Only visible in Signup Mode)
            if (!_isLoginMode)
              TextField(
                controller: _usernameController,
                decoration: const InputDecoration(labelText: "Username"),
              ),

            // EMAIL
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: "Email"),
            ),

            // PASSWORD
            TextField(
              controller: _passwordController,
              obscureText: true, // Hide password
              decoration: const InputDecoration(labelText: "Password"),
            ),

            const SizedBox(height: 20),

            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: handleAuth,
                    child: Text(_isLoginMode ? "Login" : "Sign Up"),
                  ),

            // TOGGLE BUTTON
            TextButton(
              onPressed: () {
                setState(() {
                  _isLoginMode = !_isLoginMode;
                });
              },
              child: Text(
                _isLoginMode
                    ? "Don't have an account? Sign Up"
                    : "Already have an account? Login",
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------
// SCREEN 2: USER LIST (CONTACTS)
// -----------------------------------
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
    _setupSocketListeners();
    // Request initial list
    widget.socket.emit('get_users');
  }

  void _setupSocketListeners() {
    // Update list when server sends it
    widget.socket.on('users_list', (data) {
      if (mounted) setState(() => _users = data);
    });

    // Real-time status updates
    widget.socket.on('user_status_change', (data) {
      if (mounted) {
        setState(() {
          final index = _users.indexWhere((u) => u['_id'] == data['userId']);
          if (index != -1) {
            _users[index]['is_online'] = data['isOnline'];
          }
        });
      }
    });
  }

  void _handleUserTap(dynamic user) {
    // 1. Tell server we want to chat
    widget.socket.emit('join_private_chat', user['_id']);

    // 2. Wait for Room Ready (Using .once to avoid duplicate listeners)
    widget.socket.once('private_chat_ready', (data) {
      final roomId = data['roomId'];
      final history = List<Map<String, dynamic>>.from(data['history']);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            socket: widget.socket,
            username: widget.currentUser['username'], // My Name
            otherUserName: user['username'], // Their Name (for AppBar)
            userId: widget.currentUser['_id'],
            roomId: roomId,
            initialHistory: history,
          ),
        ),
      );
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
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          final isOnline = user['is_online'] ?? false;

          // Don't show yourself in the list (Optional optimization)
          if (user['_id'] == widget.currentUser['_id']) {
            return const SizedBox.shrink();
          }

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: isOnline ? Colors.green : Colors.grey,
              child: const Icon(Icons.person, color: Colors.white),
            ),
            title: Text(user['username']),
            subtitle: Text(isOnline ? "Online" : "Offline"),
            onTap: () => _handleUserTap(user),
          );
        },
      ),
    );
  }
}

// -----------------------------------
// SCREEN 3: THE CHAT ROOM
// -----------------------------------
class ChatScreen extends StatefulWidget {
  final IO.Socket socket;
  final String username; // My Name
  final String otherUserName; // Who I am talking to
  final String userId;
  final String roomId;
  final List<Map<String, dynamic>> initialHistory;

  const ChatScreen({
    super.key,
    required this.socket,
    required this.username,
    required this.otherUserName,
    required this.userId,
    required this.roomId,
    required this.initialHistory,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;
  String _typingUser = '';
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    // Load history
    _messages.addAll(widget.initialHistory);

    // Safety: Ensure we are in the room
    widget.socket.emit('join_room', widget.roomId);

    // Listeners
    setupSocketListeners();
  }

  @override
  void dispose() {
    // Cleanup to prevent memory leaks and ghost typing
    _typingTimer?.cancel();
    _messageController.dispose();

    // IMPORTANT: Turn off specific listeners for this screen so they don't
    // duplicate if we come back later.
    widget.socket.off('chat_message');
    widget.socket.off('display_typing');
    widget.socket.off('hide_typing');
    super.dispose();
  }

  void setupSocketListeners() {
    // 1. Listen for new messages
    widget.socket.on('chat_message', (data) {
      if (mounted) {
        setState(() => _messages.add(data));
      }
    });

    // 2. Listen for Typing (Merged from your nested function)
    widget.socket.on('display_typing', (data) {
      // Don't show typing if it's me (just in case)
      if (data['username'] == widget.username) return;

      print("🔔 CLIENT HEARD: Someone is typing!");
      if (mounted) {
        setState(() {
          _isTyping = true;
          _typingUser = data['username'];
        });
      }
    });

    // 3. Listen for Stop Typing
    widget.socket.on('hide_typing', (_) {
      print("🔕 CLIENT HEARD: They stopped.");
      if (mounted) {
        setState(() => _isTyping = false);
      }
    });
  }

  void sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    Map<String, dynamic> msgData = {
      'content': _messageController.text.trim(),
      'roomId': widget.roomId,
    };

    widget.socket.emit('chat_message', msgData);
    _messageController.clear();
  }

  void _onTextChanged(String text) {
    // 1. Emit typing event
    widget.socket.emit('typing', widget.roomId);

    // 2. Debounce logic (wait for pause)
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();

    _typingTimer = Timer(const Duration(milliseconds: 2000), () {
      widget.socket.emit('stop_typing', widget.roomId);
    });
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return "Now";
    try {
      final DateTime date = DateTime.parse(isoString).toLocal();
      return DateFormat('jm').format(date);
    } catch (e) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F5F5),
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.black),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherUserName,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            if (_isTyping)
              Text(
                "$_typingUser is typing...",
                style: const TextStyle(
                  color: Color.fromARGB(255, 5, 61, 103),
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Chat History
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['sender_id'] == widget.userId;

                return MessageBubble(
                  sender: msg['sender_name'] ?? 'Unknown',
                  text: msg['content'] ?? '',
                  time: _formatTime(msg['timestamp']),
                  isMe: isMe,
                );
              },
            ),
          ),

          // Input Area
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 8.0,
              vertical: 10.0,
            ),
            color: const Color(0xFFF5F5F5),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: TextField(
                      controller: _messageController,
                      onChanged: _onTextChanged,
                      decoration: const InputDecoration(
                        hintText: "Type a message...",
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFF007AFF),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.white, size: 20),
                    onPressed: sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------
// WIDGET: MESSAGE BUBBLE
// -----------------------------------
class MessageBubble extends StatelessWidget {
  final String sender;
  final String text;
  final String time;
  final bool isMe;

  const MessageBubble({
    super.key,
    required this.sender,
    required this.text,
    required this.time,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth:
              MediaQuery.of(context).size.width * 0.70, // Increased slightly
        ),
        child: Container(
          // Optimized margins so bubbles don't get squashed
          margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          decoration: BoxDecoration(
            color: isMe ? const Color(0xFF007AFF) : const Color(0xFFE5E5EA),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
              bottomRight: isMe ? Radius.zero : const Radius.circular(16),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Show sender name only if it's NOT me
              if (!isMe)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: Text(
                    sender,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700],
                    ),
                  ),
                ),

              Text(
                text,
                style: TextStyle(
                  color: isMe ? Colors.white : Colors.black87,
                  fontSize: 16,
                ),
              ),

              const SizedBox(height: 5),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  time,
                  style: TextStyle(
                    color: isMe ? Colors.white70 : Colors.black54,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
