import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
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

  // FIX 1: Add a ScrollController
  final ScrollController _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [];
  bool _isTyping = false;
  String _typingUser = '';
  Timer? _typingTimer;
  late IO.Socket _socket;

  @override
  void initState() {
    super.initState();
    _messages.addAll(widget.initialHistory);

    _socket = ref.read(socketServiceProvider).socket;

    // FIX 2: Scroll to bottom immediately after the screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    Future.microtask(() => _setupSocketListeners());
  }

  // FIX 3: Helper function to scroll down
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _setupSocketListeners() {
    if (!mounted) return;

    // Safety join
    _socket.emit('join_room', widget.roomId);

    // 1. Message Listener
    _socket.on('chat_message', (data) {
      if (!mounted) return;
      if (data['roomId'] != widget.roomId) return;

      setState(() {
        _messages.add(data);
      });

      // FIX 4: Scroll down when receiving a message
      // We wait for the frame to render the new bubble, then scroll
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });

    // 2. Typing Listener
    _socket.on('display_typing', (data) {
      if (!mounted) return;
      if (data['username'] == ref.read(authProvider).user?.username) return;
      if (data['roomId'] != widget.roomId) return;

      setState(() {
        _isTyping = true;
        _typingUser = data['username'];
      });

      // FIX 5: Scroll down if typing indicator pushes content up
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });

    // 3. Stop Typing Listener
    _socket.on('hide_typing', (data) {
      if (!mounted) return;
      if (data is Map && data['roomId'] != widget.roomId) return;

      setState(() => _isTyping = false);
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose(); // FIX 6: Clean up controller

    _socket.off('chat_message');
    _socket.off('display_typing');
    _socket.off('hide_typing');

    super.dispose();
  }

  void sendMessage() {
    if (_messageController.text.trim().isEmpty) return;

    Map<String, dynamic> msgData = {
      'content': _messageController.text.trim(),
      'roomId': widget.roomId,
    };

    _socket.emit('chat_message', msgData);
    _messageController.clear();

    // FIX 7: Scroll down immediately when we send
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _onTextChanged(String text) {
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
              // FIX 8: Attach the controller
              controller: _scrollController,
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
