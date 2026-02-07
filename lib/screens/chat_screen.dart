// lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import '../app_theme.dart';
import '../services/audio_service.dart';

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

  // Audio Service State
  final AudioService _audioService = AudioService();
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    // ✅ CRITICAL FIX:
    // Connect to the socket ONLY when the screen is ready.
    // This prevents "Missing History" race conditions.
    Future.microtask(() {
      ref
          .read(chatProvider.notifier)
          .joinChat(widget.roomId, widget.otherUserId, widget.initialHistory);
    });
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

  @override
  void dispose() {
    _audioService.dispose(); // Clean up audio resources
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- Audio Recording Logic ---
  Future<void> _startRecording() async {
    setState(() => _isRecording = true);
    await _audioService.startRecording();
  }

  Future<void> _stopAndSendRecording() async {
    setState(() => _isRecording = false);
    final path = await _audioService.stopRecording();

    if (path != null) {
      // 1. Upload Audio
      final url = await _audioService.uploadAudio(path);

      // 2. Send Message
      if (url != null) {
        ref.read(chatProvider.notifier).sendMessage(url, type: 'audio');
      }
    }
  }

  void _handleSend() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    ref.read(chatProvider.notifier).sendMessage(text);
    _messageController.clear();
    setState(() {}); // Refresh UI (toggle Mic/Send button)
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final myUserId = ref.watch(authProvider).user?.id;

    // Auto-scroll when new messages arrive
    ref.listen(chatProvider, (previous, next) {
      if (next.messages.length > (previous?.messages.length ?? 0)) {
        Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
      }
    });

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
            if (chatState.isTyping)
              Text(
                "${chatState.typingUser ?? 'Someone'} is typing...",
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
          // --- Message List ---
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: chatState.messages.length,
              itemBuilder: (context, index) {
                final msg = chatState.messages[index];
                final isMe = msg['sender_id'] == myUserId;
                final isDeleted = msg['isDeleted'] == true;

                // Handle Deleted Message UI
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
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
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
                      ? () => _handleDeleteMessage(context, msg['_id'])
                      : null,
                  child: MessageBubble(
                    sender: msg['sender_name'] ?? 'Unknown',
                    senderAvatar: msg['sender_avatar'],
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

          // --- Input Area ---
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
                // Photo Button
                IconButton(
                  icon: chatState.isUploading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.add_photo_alternate_rounded,
                          color: Colors.grey[600],
                        ),
                  onPressed: chatState.isUploading
                      ? null
                      : () => ref.read(chatProvider.notifier).sendImage(),
                ),
                const SizedBox(width: 8),

                // Text Field
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    onChanged: (text) {
                      setState(() {}); // Toggle Mic/Send button
                      ref.read(chatProvider.notifier).sendTypingEvent(text);
                    },
                    onSubmitted: (_) => _handleSend(),
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

                // Mic or Send Button
                _messageController.text.trim().isEmpty
                    ? GestureDetector(
                        onLongPressStart: (_) => _startRecording(),
                        onLongPressEnd: (_) => _stopAndSendRecording(),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: _isRecording ? Colors.red : AppTheme.primary,
                            shape: BoxShape.circle,
                            boxShadow: _isRecording
                                ? [
                                    BoxShadow(
                                      color: Colors.red.withOpacity(0.5),
                                      blurRadius: 10,
                                      spreadRadius: 2,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Icon(
                            _isRecording ? Icons.mic : Icons.mic_none,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      )
                    : Container(
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
                          onPressed: _handleSend,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _handleDeleteMessage(BuildContext context, String messageId) {
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
              ref.read(chatProvider.notifier).deleteMessage(messageId);
              Navigator.pop(ctx);
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? isoString) {
    if (isoString == null) return "Now";
    try {
      return DateFormat('jm').format(DateTime.parse(isoString).toLocal());
    } catch (e) {
      return "";
    }
  }
}
