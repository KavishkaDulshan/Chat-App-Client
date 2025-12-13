import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO; // Import types
import '../providers/socket_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String otherUserName;
  final String roomId;
  final List<Map<String, dynamic>> initialHistory;

  const ChatScreen({
    super.key,
    required this.otherUserName,
    required this.roomId,
    required this.initialHistory,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;
  String _typingUser = '';
  Timer? _typingTimer;

  // FIX 1: Store socket locally to avoid using 'ref' in dispose
  late IO.Socket _socket;

  @override
  void initState() {
    super.initState();
    _messages.addAll(widget.initialHistory);

    // FIX 2: Initialize the local socket variable immediately
    _socket = ref.read(socketServiceProvider).socket;

    // Defer the setup logic, but use the local _socket variable
    Future.microtask(() => _setupSocketListeners());
  }

  void _setupSocketListeners() {
    // Safety check: If screen closed before this runs, stop.
    if (!mounted) return;

    final myUsername = ref.read(authProvider).user?.username;

    // Safety join
    _socket.emit('join_room', widget.roomId);

    // 1. Message Listener
    _socket.on('chat_message', (data) {
      // FIX 3: Check mounted before SetState
      if (!mounted) return;
      if (data['roomId'] != widget.roomId) return;

      setState(() => _messages.add(data));
    });

    // 2. Typing Listener
    _socket.on('display_typing', (data) {
      if (!mounted) return; // Safety Check
      if (data['username'] == myUsername) return;
      if (data['roomId'] != widget.roomId) return;

      setState(() {
        _isTyping = true;
        _typingUser = data['username'];
      });
    });

    // 3. Stop Typing Listener
    _socket.on('hide_typing', (data) {
      if (!mounted) return; // Safety Check
      if (data is Map && data['roomId'] != widget.roomId) return;

      setState(() => _isTyping = false);
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _messageController.dispose();

    // FIX 4: Use the local '_socket' variable.
    // DO NOT use 'ref.read' here. It causes the "Bad State" error.
    _socket.off('chat_message');
    _socket.off('display_typing');
    _socket.off('hide_typing');

    super.dispose();
  }

  void sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    // Use local variable
    Map<String, dynamic> msgData = {
      'content': _messageController.text.trim(),
      'roomId': widget.roomId,
    };

    _socket.emit('chat_message', msgData);
    _messageController.clear();
  }

  void _onTextChanged(String text) {
    // Use local variable
    _socket.emit('typing', widget.roomId);

    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 2000), () {
      _socket.emit('stop_typing', widget.roomId);
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
    final myUserId = ref.watch(authProvider).user?.id;

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
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['sender_id'] == myUserId;

                return MessageBubble(
                  sender: msg['sender_name'] ?? 'Unknown',
                  text: msg['content'] ?? '',
                  time: _formatTime(msg['timestamp']),
                  isMe: isMe,
                );
              },
            ),
          ),
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
