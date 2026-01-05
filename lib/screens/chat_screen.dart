import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../providers/socket_provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/message_bubble.dart';
import '../services/image_service.dart';
import '../app_theme.dart';

class ChatScreen extends ConsumerStatefulWidget {
  final String otherUserName;
  final String roomId;
  final List<Map<String, dynamic>> initialHistory;
  final bool isDesktop;

  const ChatScreen({
    super.key,
    required this.otherUserName,
    required this.roomId,
    required this.initialHistory,
    this.isDesktop = false,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImageService _imageService = ImageService();

  // We keep using Map to stay compatible with your stable code
  final List<Map<String, dynamic>> _messages = [];

  bool _isTyping = false;
  bool _isUploading = false;
  String _typingUser = '';
  Timer? _typingTimer;
  late IO.Socket _socket;

  @override
  void initState() {
    super.initState();
    // Load history
    _messages.addAll(widget.initialHistory);

    _socket = ref.read(socketServiceProvider).socket;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    Future.microtask(() => _setupSocketListeners());
  }

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
    _socket.emit('join_room', widget.roomId);

    // 1. Listen for New Messages
    _socket.on('chat_message', (data) {
      if (!mounted) return;
      if (data['roomId'] != widget.roomId) return;
      setState(() => _messages.add(data));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });

    // 2. NEW: Listen for Deleted Messages
    _socket.on('message:deleted', (messageId) {
      if (!mounted) return;
      setState(() {
        // Find the message by ID and mark it as deleted
        for (var msg in _messages) {
          if (msg['_id'] == messageId) {
            msg['isDeleted'] = true;
            msg['content'] = 'This message was deleted';
          }
        }
      });
    });

    // 3. Typing Indicators
    _socket.on('display_typing', (data) {
      if (!mounted) return;
      if (data['username'] == ref.read(authProvider).user?.username) return;
      if (data['roomId'] != widget.roomId) return;
      setState(() {
        _isTyping = true;
        _typingUser = data['username'];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    });

    _socket.on('hide_typing', (data) {
      if (!mounted) return;
      if (data is Map && data['roomId'] != widget.roomId) return;
      setState(() => _isTyping = false);
    });
  }

  // === NEW: Handle Delete Action ===
  void _handleDeleteMessage(String messageId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Message?"),
        content: const Text("This will remove the message for everyone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              // Emit Delete Event to Server
              _socket.emit('message:delete', {
                'messageId': messageId,
                'roomId': widget.roomId,
              });
              Navigator.pop(ctx);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _handleImageSend() async {
    final File? file = await _imageService.pickImage();
    if (file == null) return;
    setState(() => _isUploading = true);
    final String? imageUrl = await _imageService.uploadImage(file);
    setState(() => _isUploading = false);
    if (imageUrl != null) {
      _socket.emit('chat_message', {
        'content': imageUrl,
        'roomId': widget.roomId,
        'type': 'image',
      });
    }
  }

  void sendMessage() {
    if (_messageController.text.trim().isEmpty) return;
    _socket.emit('chat_message', {
      'content': _messageController.text.trim(),
      'roomId': widget.roomId,
      'type': 'text',
    });
    _messageController.clear();
  }

  void _onTextChanged(String text) {
    _socket.emit('typing', widget.roomId);
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _typingTimer = Timer(
      const Duration(milliseconds: 2000),
      () => _socket.emit('stop_typing', widget.roomId),
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();
    _socket.off('chat_message');
    _socket.off('message:deleted'); // Clean up listener
    _socket.off('display_typing');
    _socket.off('hide_typing');
    super.dispose();
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return "Now";
    try {
      return DateFormat('jm').format(DateTime.parse(isoString).toLocal());
    } catch (e) {
      return "";
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUserId = ref.watch(authProvider).user?.id;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        leading: widget.isDesktop
            ? const SizedBox()
            : const BackButton(color: Colors.black),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.otherUserName, style: AppTheme.nameStyle),
            if (_isTyping)
              Text(
                "$_typingUser is typing...",
                style: TextStyle(
                  color: AppTheme.primary,
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
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isMe = msg['sender_id'] == myUserId;
                final isDeleted = msg['isDeleted'] == true;

                // 1. DELETED MESSAGE UI
                if (isDeleted) {
                  return Align(
                    alignment: isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Icon(Icons.block, size: 14, color: Colors.grey),
                          SizedBox(width: 5),
                          Text(
                            "This message was deleted",
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: Colors.grey,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                // 2. NORMAL MESSAGE (With Long Press)
                return GestureDetector(
                  onLongPress: isMe
                      ? () => _handleDeleteMessage(msg['_id'])
                      : null,
                  child: MessageBubble(
                    sender: msg['sender_name'] ?? 'Unknown',
                    text: msg['content'] ?? '',
                    time: _formatTime(msg['timestamp']),
                    isMe: isMe,
                    type: msg['type'] ?? 'text',
                  ),
                );
              },
            ),
          ),

          // INPUT AREA
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              children: [
                IconButton(
                  icon: _isUploading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.add_photo_alternate_rounded,
                          color: Colors.grey[600],
                        ),
                  onPressed: _isUploading ? null : _handleImageSend,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onChanged: _onTextChanged,
                    onSubmitted: (_) => sendMessage(),
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      filled: true,
                      fillColor: AppTheme.background,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: const BoxDecoration(
                    color: AppTheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
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
