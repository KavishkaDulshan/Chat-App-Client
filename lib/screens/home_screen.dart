import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/conversations_provider.dart';
import '../providers/contact_provider.dart';
import 'chat_screen.dart';
import 'contact_requests_screen.dart';
import '../app_theme.dart';
import '../models/conversation.dart';
import 'profile_screen.dart';
import 'login_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(conversationsProvider.notifier).loadChats();
      ref.read(contactProvider.notifier).init();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authProvider.notifier).logout();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text("Logout", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _joinChat(Conversation conv) {
    final myUser = ref.read(authProvider).user;
    if (myUser == null) return;

    String roomId = conv.id;
    if (roomId.isEmpty) {
      final ids = [myUser.id, conv.otherUserId];
      ids.sort();
      roomId = ids.join("_");
    }

    // Reset unread count instantly
    ref.read(conversationsProvider.notifier).resetUnreadCount(roomId);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserName: conv.otherUserName,
          otherUserId: conv.otherUserId,
          roomId: roomId,
          initialHistory: const [],
        ),
      ),
    ).then((_) {
      _searchController.clear();
      if (_searchController.text.isEmpty) {
        ref.read(conversationsProvider.notifier).loadChats();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final convState = ref.watch(conversationsProvider);
    final contactState = ref.watch(contactProvider);
    final pendingCount = contactState.pendingCount;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text("Messages", style: AppTheme.headerStyle),
        backgroundColor: AppTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        actions: [
          // Contact Requests badge
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.person_add_alt_1_outlined,
                  color: AppTheme.textPrimary,
                  size: 26,
                ),
                tooltip: 'Contact Requests',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const ContactRequestsScreen()),
                ).then((_) =>
                    ref.read(contactProvider.notifier).loadPendingRequests()),
              ),
              if (pendingCount > 0)
                Positioned(
                  top: 8,
                  right: 6,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 18),
                      child: Text(
                        pendingCount > 9 ? '9+' : '$pendingCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(
              Icons.person_outline,
              color: AppTheme.textPrimary,
              size: 28,
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.logout_rounded,
              color: Colors.redAccent,
              size: 26,
            ),
            onPressed: _handleLogout,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // 1. Search bar
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 12.0,
            ),
            color: AppTheme.background,
            child: TextField(
              controller: _searchController,
              onChanged: (val) {
                setState(() {}); // Update clear icon visibility
                _searchDebounce?.cancel();
                if (val.isEmpty) {
                  // Clear search immediately
                  ref.read(conversationsProvider.notifier).searchUsers(val);
                } else {
                  _searchDebounce = Timer(const Duration(milliseconds: 400), () {
                    ref.read(conversationsProvider.notifier).searchUsers(val);
                  });
                }
              },
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: "Search for people...",
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppTheme.textSecondary,
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear,
                            color: AppTheme.textSecondary, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(conversationsProvider.notifier)
                              .searchUsers('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.cardColor,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFFE2E8F0),
                    width: 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppTheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),

          // 2. Unified list
          Expanded(
            child: convState.conversations.isEmpty && convState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : convState.conversations.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        itemCount: convState.conversations.length,
                        cacheExtent: 300,
                        addAutomaticKeepAlives: false,
                        itemBuilder: (context, index) {
                          final conversation = convState.conversations[index];
                          return _buildConversationTile(conversation);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final isSearching = _searchController.text.isNotEmpty;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearching ? Icons.search_off : Icons.chat_bubble_outline,
            size: 52,
            color: AppTheme.textSecondary,
          ),
          const SizedBox(height: 16),
          Text(
            isSearching ? 'No users found' : 'No conversations yet',
            style: const TextStyle(
              fontSize: 16,
              color: AppTheme.textSecondary,
            ),
          ),
          if (!isSearching) ...[
            const SizedBox(height: 8),
            const Text(
              'Search for people to connect with',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConversationTile(Conversation conv) {
    // Search result: show contact-status-aware tile
    if (conv.id.isEmpty) {
      return _buildSearchResultTile(conv);
    }
    // Normal conversation tile
    return _buildChatTile(conv);
  }

  // ── Normal conversation tile ────────────────────────────────────────────────
  Widget _buildChatTile(Conversation conv) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            _buildCachedAvatar(
              url: conv.otherUserAvatar,
              fallbackChar: conv.otherUserName.isNotEmpty
                  ? conv.otherUserName[0].toUpperCase()
                  : "?",
              radius: 28,
            ),
            if (conv.isOnline)
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
          ],
        ),
        title: Text(conv.otherUserName, style: AppTheme.nameStyle),
        subtitle: _buildLastMessagePreview(conv),
        trailing: conv.unreadCount > 0
            ? Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(
                    conv.unreadCount > 99 ? '99+' : '${conv.unreadCount}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : null,
        onTap: () => _joinChat(conv),
      ),
    );
  }

  // ── Search result tile with context-aware action ────────────────────────────
  Widget _buildSearchResultTile(Conversation conv) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                _buildCachedAvatar(
                  url: conv.otherUserAvatar,
                  fallbackChar: conv.otherUserName.isNotEmpty
                      ? conv.otherUserName[0].toUpperCase()
                      : "?",
                  radius: 26,
                ),
                if (conv.isOnline)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            // Name
            Expanded(
              child: Text(conv.otherUserName, style: AppTheme.nameStyle),
            ),
            const SizedBox(width: 8),
            // Context-aware action button
            _ContactActionButton(conv: conv),
          ],
        ),
      ),
    );
  }

  Widget _buildLastMessagePreview(Conversation conv) {
    if (conv.lastMessageIsDeleted) {
      return Row(
        children: const [
          Icon(Icons.block, size: 16, color: Colors.grey),
          SizedBox(width: 4),
          Text(
            "This message was deleted",
            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ],
      );
    }

    final bool isAudio = conv.lastMessage.contains('/video/upload/') ||
        conv.lastMessage.endsWith('.m4a') ||
        conv.lastMessage.endsWith('.mp3');

    if (isAudio) {
      return Row(
        children: const [
          Icon(Icons.mic, size: 16, color: AppTheme.primary),
          SizedBox(width: 4),
          Text("Voice Message", style: TextStyle(color: Colors.grey)),
        ],
      );
    }

    final bool isImage = conv.lastMessage.contains('📷 Photo') ||
        conv.lastMessage.contains('📷 Image') ||
        conv.lastMessage.endsWith('.jpg') ||
        conv.lastMessage.endsWith('.png') ||
        conv.lastMessage.endsWith('.webp');

    if (isImage) {
      return Row(
        children: const [
          Icon(Icons.photo, size: 16, color: AppTheme.primary),
          SizedBox(width: 4),
          Text("Photo", style: TextStyle(color: Colors.grey)),
        ],
      );
    }

    if (conv.lastMessage.startsWith('e2e:v1:')) {
      return Row(
        children: const [
          Icon(Icons.lock_outline, size: 16, color: AppTheme.primary),
          SizedBox(width: 4),
          Text('Message', style: TextStyle(color: Colors.grey)),
        ],
      );
    }

    return Text(
      conv.lastMessage,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.subTitleStyle,
    );
  }

  Widget _buildCachedAvatar({
    required String? url,
    required String fallbackChar,
    required double radius,
  }) {
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
        child: Text(
          fallbackChar,
          style: TextStyle(
            color: AppTheme.primary,
            fontSize: radius * 0.65,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      maxWidthDiskCache: 128,
      maxHeightDiskCache: 128,
      memCacheWidth: (radius * 2).toInt(),
      memCacheHeight: (radius * 2).toInt(),
      imageBuilder: (context, imageProvider) => CircleAvatar(
        radius: radius,
        backgroundImage: imageProvider,
      ),
      placeholder: (context, url) => CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      errorWidget: (context, url, error) => CircleAvatar(
        radius: radius,
        backgroundColor: AppTheme.primary.withValues(alpha: 0.2),
        child: Text(
          fallbackChar,
          style: TextStyle(
            color: AppTheme.primary,
            fontSize: radius * 0.65,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// ── Context-aware contact action button ──────────────────────────────────────
class _ContactActionButton extends ConsumerStatefulWidget {
  final Conversation conv;
  const _ContactActionButton({required this.conv});

  @override
  ConsumerState<_ContactActionButton> createState() =>
      _ContactActionButtonState();
}

class _ContactActionButtonState extends ConsumerState<_ContactActionButton> {
  bool _isLoading = false;
  late String _status;

  @override
  void initState() {
    super.initState();
    _status = widget.conv.contactStatus;
  }

  @override
  void didUpdateWidget(covariant _ContactActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.conv.contactStatus != widget.conv.contactStatus) {
      setState(() {
        _status = widget.conv.contactStatus;
      });
    }
  }

  Future<void> _sendRequest() async {
    setState(() => _isLoading = true);
    final result = await ref
        .read(contactProvider.notifier)
        .sendRequest(widget.conv.otherUserId);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _status = result == 'error' ? _status : 'pending_sent';
      });
      if (result == 'error') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to send request. Try again.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      } else if (result == 'accepted') {
        // They had sent us a request — now we're contacts
        setState(() => _status = 'contacts');
      }
    }
  }

  Future<void> _accept() async {
    final requestId = widget.conv.pendingRequestId ?? '';
    if (requestId.isEmpty) return;
    setState(() => _isLoading = true);
    final ok = await ref
        .read(contactProvider.notifier)
        .acceptRequest(requestId, widget.conv.otherUserId);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _status = ok ? 'contacts' : _status;
      });
    }
  }

  Future<void> _decline() async {
    final requestId = widget.conv.pendingRequestId ?? '';
    if (requestId.isEmpty) return;
    setState(() => _isLoading = true);
    await ref
        .read(contactProvider.notifier)
        .declineRequest(requestId, widget.conv.otherUserId);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _status = 'none';
      });
    }
  }

  void _openChat() {
    final myUser = ref.read(authProvider).user;
    if (myUser == null) return;
    final ids = [myUser.id, widget.conv.otherUserId];
    ids.sort();
    final roomId = ids.join('_');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserName: widget.conv.otherUserName,
          otherUserId: widget.conv.otherUserId,
          roomId: roomId,
          initialHistory: const [],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    switch (_status) {
      case 'contacts':
        return _actionChip(
          label: 'Message',
          icon: Icons.chat_bubble_outline,
          color: AppTheme.primary,
          textColor: Colors.white,
          onTap: _openChat,
        );

      case 'pending_sent':
        return _actionChip(
          label: 'Requested',
          icon: Icons.schedule,
          color: const Color(0xFFF1F5F9),
          textColor: AppTheme.textSecondary,
          onTap: null,
        );

      case 'pending_received':
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _decline,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child:
                    const Icon(Icons.close, color: Colors.redAccent, size: 16),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _accept,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Accept',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        );

      default: // 'none'
        return _actionChip(
          label: 'Add',
          icon: Icons.person_add_alt_1,
          color: AppTheme.primary,
          textColor: Colors.white,
          onTap: _sendRequest,
        );
    }
  }

  Widget _actionChip({
    required String label,
    required IconData icon,
    required Color color,
    required Color textColor,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: textColor, size: 14),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
