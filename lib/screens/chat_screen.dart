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
  final String otherUserId;
  final String roomId;
  final List<Map<String, dynamic>> initialHistory;
  final bool isDesktop;

  const ChatScreen({
    super.key,
    required this.otherUserName,
    required this.otherUserId,
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

  final List<Map<String, dynamic>> _messages = [];
  String _activeRoomId = "";

  bool _isTyping = false;
  bool _isUploading = false;
  String _typingUser = '';
  Timer? _typingTimer;
  late IO.Socket _socket;

  // Handler definitions
  late Function(dynamic) _messageHandler;
  late Function(dynamic) _typingHandler;
  late Function(dynamic) _stopTypingHandler;

  @override
  void initState() {
    super.initState();
    _activeRoomId = widget.roomId;
    _messages.addAll(widget.initialHistory);
    _socket = ref.read(socketServiceProvider).socket;

    // --- 1. DEFINE HANDLERS ---
    _messageHandler = (data) {
      if (!mounted) return;
      if (data['roomId'] != _activeRoomId && data['roomId'] != widget.roomId) {
        return;
      }

      // PREVENT DUPLICATES
      final isDuplicate = _messages.any((msg) => msg['_id'] == data['_id']);
      if (isDuplicate) return;

      setState(() => _messages.add(data));
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

      final myUserId = ref.read(authProvider).user?.id;
      if (data['sender_id'] != myUserId) {
        _socket.emit('conversation:read', {'roomId': _activeRoomId});
      }
    };

    _typingHandler = (data) {
      if (!mounted) return;
      if (data['username'] == ref.read(authProvider).user?.username) return;
      if (data['roomId'] != _activeRoomId) return;
      setState(() {
        _isTyping = true;
        _typingUser = data['username'];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    };

    _stopTypingHandler = (data) {
      if (!mounted) return;
      if (data is Map && data['roomId'] != _activeRoomId) return;
      setState(() => _isTyping = false);
    };

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

    // 1. Join the Room (for history loading logic on backend)
    _socket.emit('join_private_chat', widget.otherUserId);

    // 2. Attach Named Listeners
    _socket.on('chat_message', _messageHandler); // <--- ONLY THIS ONE
    _socket.on('display_typing', _typingHandler);
    _socket.on('hide_typing', _stopTypingHandler);

    // 3. One-time listener for History
    _socket.on('private_chat_ready', (data) {
      if (!mounted) return;
      setState(() {
        _activeRoomId = data['roomId'];
        _messages.clear();
        _messages.addAll(List<Map<String, dynamic>>.from(data['history']));
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
        _socket.emit('conversation:read', {'roomId': _activeRoomId});
      });
    });

    // 4. Other Status Updates
    _socket.on('conversation:read_ack', (data) {
      if (!mounted) return;
      final readerId = data['readerId'];
      final myUserId = ref.read(authProvider).user?.id;

      if (data['roomId'] == _activeRoomId && readerId != myUserId) {
        setState(() {
          for (var msg in _messages) {
            if (msg['sender_id'] == myUserId) msg['status'] = 'read';
          }
        });
      }
    });

    _socket.on('message:status_update', (data) {
      if (!mounted) return;
      if (data['roomId'] == _activeRoomId) {
        setState(() {
          for (var msg in _messages) {
            if (msg['_id'] == data['messageId']) msg['status'] = data['status'];
          }
        });
      }
    });

    _socket.on('message:deleted', (messageId) {
      if (!mounted) return;
      setState(() {
        for (var msg in _messages) {
          if (msg['_id'] == messageId) {
            msg['isDeleted'] = true;
            msg['content'] = 'This message was deleted';
          }
        }
      });
    });
  }

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
              _socket.emit('message:delete', {
                'messageId': messageId,
                'roomId': _activeRoomId,
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
        'roomId': _activeRoomId,
        'type': 'image',
      });
    }
  }

  void sendMessage() {
    if (_messageController.text.trim().isEmpty) return;
    _socket.emit('chat_message', {
      'content': _messageController.text.trim(),
      'roomId': _activeRoomId,
      'type': 'text',
    });
    _messageController.clear();
  }

  void _onTextChanged(String text) {
    _socket.emit('typing', _activeRoomId);
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _typingTimer = Timer(
      const Duration(milliseconds: 2000),
      () => _socket.emit('stop_typing', _activeRoomId),
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _messageController.dispose();
    _scrollController.dispose();

    // SAFE REMOVAL: Only remove OUR specific listeners
    _socket.off('chat_message', _messageHandler);
    _socket.off('display_typing', _typingHandler);
    _socket.off('hide_typing', _stopTypingHandler);

    // Global generic listeners can be removed if strictly necessary,
    // but usually better to leave generic ones or use named handlers for them too.
    _socket.off('message:deleted');
    _socket.off('conversation:read_ack');
    _socket.off('message:status_update');
    _socket.off('private_chat_ready');

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
                    status: msg['status'] ?? 'sent',
                  ),
                );
              },
            ),
          ),
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
