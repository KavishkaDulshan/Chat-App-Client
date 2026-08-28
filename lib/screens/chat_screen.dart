// lib/screens/chat_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/conversations_provider.dart';
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

    // Mark this room as actively viewed — uses top-level variable, no ref issues.
    currentlyViewingRoomId = widget.roomId;

    Future.microtask(() {
      ref
          .read(chatProvider.notifier)
          .joinChat(widget.roomId, widget.otherUserId, widget.initialHistory);
      // Also reset the badge immediately
      ref.read(conversationsProvider.notifier).resetUnreadCount(widget.roomId);
    });
    _scrollController.addListener(_onScroll);
  }

  // Placed in didChangeDependencies so it's only registered once
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 50) {
      ref.read(chatProvider.notifier).loadMoreMessages();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _audioService.dispose();
    _messageController.dispose();
    _scrollController.dispose();

    // Clear the "currently viewing" flag — plain variable, no ref needed.
    // This is 100% safe in dispose() since it's just a top-level assignment.
    currentlyViewingRoomId = '';

    // Also clear chatProvider's activeRoomId so its message handler stops
    // matching messages from this room and emitting phantom conversation:read.
    // ref.read() on a Notifier field (not state) is safe before super.dispose().
    try {
      ref.read(chatProvider.notifier).clearActiveRoom();
    } catch (_) {
      // Silently handle edge cases where ref is already invalidated
    }

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

  Future<void> _handleSend() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    await ref.read(chatProvider.notifier).sendMessage(text);
    _messageController.clear();
    setState(() {}); // Refresh UI (toggle Mic/Send buttons)
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(chatProvider);
    final myUserId = ref.watch(authProvider).user?.id;

    // Auto-scroll when new messages arrive (registered once via listen, not in build)
    ref.listen<ChatState>(chatProvider, (previous, next) {
      final prevLen = previous?.messages.length ?? 0;
      if (next.messages.length > prevLen && !next.isLoadingMore) {
        if (_scrollController.hasClients && _scrollController.position.pixels < 100) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        }
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        leading: widget.isDesktop ? const SizedBox() : const BackButton(),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.otherUserName, style: AppTheme.nameStyle),
            if (chatState.isTyping)
              Text(
                "${chatState.typingUser ?? 'Someone'} is typing...",
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.0),
          child: Container(color: const Color(0xFFE2E8F0), height: 1.0),
        ),
      ),
      body: Column(
        children: [
          // --- Message List ---
          Expanded(
            child: Column(
              children: [
                // BUG-1: Loading indicator when fetching older messages
                if (chatState.isLoadingMore)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                Expanded(
                  child: chatState.isLoading && chatState.messages.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : ListView.builder(
                        reverse: true,
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 20),
                        itemCount: chatState.messages.length,
                        cacheExtent: 300, // Reduce off-screen rendering for low-end devices
                        addAutomaticKeepAlives: false, // Don't keep off-screen items alive
                        itemBuilder: (context, index) {
                          final msg = chatState.messages[chatState.messages.length - 1 - index];
                          final isMe = msg['sender_id'] == myUserId;
                          final isDeleted = msg['isDeleted'] == true;

                          if (isDeleted) {
                            return RepaintBoundary(
                              child: Align(
                                alignment: isMe
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 5),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8,
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
                              ),
                            );
                          }

                          return RepaintBoundary(
                            child: GestureDetector(
                              onLongPress: isMe
                                  ? () => _handleDeleteMessage(context, msg['_id'])
                                  : null,
                              child: MessageBubble(
                                key: ValueKey(msg['_id']),
                                sender: msg['sender_name'] ?? 'Unknown',
                                senderAvatar: msg['sender_avatar'],
                                text: msg['content'] ?? '',
                                time: _formatTime(msg['timestamp']),
                                isMe: isMe,
                                type: msg['type'] ?? 'text',
                                status: msg['status'] ?? 'sent',
                              ),
                            ),
                          );
                        },
                      ),
                ),
              ],
            ),
          ),

          // --- Input Area ---
          SafeArea(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.background,
                border: Border(
                  top: BorderSide(color: const Color(0xFFE2E8F0), width: 1),
                ),
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
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
                      onChanged: (text) {
                        setState(() {}); // Toggle Mic/Send button
                        ref.read(chatProvider.notifier).sendTypingEvent(text);
                      },
                      onSubmitted: (_) {
                        _handleSend();
                      },
                      decoration: InputDecoration(
                        hintText: "Type a message...",
                        hintStyle: TextStyle(color: AppTheme.textSecondary),
                        filled: true,
                        fillColor: AppTheme.cardColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                            width: 1,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: Color(0xFFE2E8F0),
                            width: 1,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(
                            color: AppTheme.primary,
                            width: 1.5,
                          ),
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
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _isRecording
                                  ? Colors.redAccent
                                  : AppTheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _isRecording ? Icons.mic : Icons.mic_none,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                            onPressed: () {
                              _handleSend();
                            },
                          ),
                        ),
                ],
              ),
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
