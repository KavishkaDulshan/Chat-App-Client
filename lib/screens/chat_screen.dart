import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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

  @override
  void initState() {
    super.initState();
    _messages.addAll(widget.initialHistory);

    // We need to run this after build to safely access providers
    Future.microtask(() => _setupSocket());
  }

  void _setupSocket() {
    final socket = ref.read(socketServiceProvider).socket;
    final myUsername = ref.read(authProvider).user?.username;

    // (Optional) We still join the room for safety, but we rely on Personal Room now
    socket.emit('join_room', widget.roomId);

    // 1. Message Listener (With FILTER)
    socket.on('chat_message', (data) {
      // --- FIX: Check if this message belongs to THIS screen ---
      if (data['roomId'] != widget.roomId) return;
      // ---------------------------------------------------------

      if (mounted) setState(() => _messages.add(data));
    });

    // 2. Typing Listener (With FILTER)
    socket.on('display_typing', (data) {
      if (data['username'] == myUsername) return;

      // --- FIX: Check if the typing is for THIS screen ---
      if (data['roomId'] != widget.roomId) return;
      // --------------------------------------------------

      if (mounted) {
        setState(() {
          _isTyping = true;
          _typingUser = data['username'];
        });
      }
    });

    // 3. Stop Typing Listener (With FILTER)
    socket.on('hide_typing', (data) {
      // --- FIX: Check filter ---
      // (Note: You might need to update server to send object {roomId} for hide_typing too,
      // currently it might send null or string. I updated server code above to send object)
      if (data is Map && data['roomId'] != widget.roomId) return;

      if (mounted) setState(() => _isTyping = false);
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _messageController.dispose();

    final socket = ref.read(socketServiceProvider).socket;
    // Remove specific listeners so they don't stack up
    socket.off('chat_message');
    socket.off('display_typing');
    socket.off('hide_typing');
    super.dispose();
  }

  void sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    final socket = ref.read(socketServiceProvider).socket;

    Map<String, dynamic> msgData = {
      'content': _messageController.text.trim(),
      'roomId': widget.roomId,
    };

    socket.emit('chat_message', msgData);
    _messageController.clear();
  }

  void _onTextChanged(String text) {
    final socket = ref.read(socketServiceProvider).socket;

    socket.emit('typing', widget.roomId);

    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _typingTimer = Timer(const Duration(milliseconds: 2000), () {
      socket.emit('stop_typing', widget.roomId);
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
