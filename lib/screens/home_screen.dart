import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/conversations_provider.dart'; // Import the new provider
import 'chat_screen.dart';
import '../app_theme.dart';
import '../models/conversation.dart'; // Import the unified model
import 'profile_screen.dart';
import 'login_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Bootstrap: Load data via Provider
    Future.microtask(
      () => ref.read(conversationsProvider.notifier).loadChats(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Logout Dialog Function
  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context), // Close Dialog
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              // 1. Close the Dialog
              Navigator.pop(context);

              // 2. Clear Riverpod State
              await ref.read(authProvider.notifier).logout();

              // 3. Force Navigate to Login & Clear Stack
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false, // This removes all previous routes
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

    // Generate Room ID locally if needed (for Search results)
    String roomId = conv.id;
    if (roomId.isEmpty) {
      final ids = [myUser.id, conv.otherUserId];
      ids.sort();
      roomId = ids.join("_");
    }

    // ❌ REMOVED: socket.emit('join_private_chat')
    // We strictly navigate first. The ChatScreen will handle the connection
    // in its initState to prevent the "Race Condition" (missing history).

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserName: conv.otherUserName,
          otherUserId: conv.otherUserId,
          roomId: roomId,
          initialHistory: const [], // Pass empty, let ChatScreen fetch it
        ),
      ),
    ).then((_) {
      // Clear search when coming back
      _searchController.clear();
      ref.read(conversationsProvider.notifier).loadChats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final convState = ref.watch(conversationsProvider);

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text("Messages", style: AppTheme.headerStyle),
        backgroundColor: AppTheme.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        actions: [
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
          // 1. CLEAN SEARCH BAR
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 20.0,
              vertical: 12.0,
            ),
            color: AppTheme.background,
            child: TextField(
              controller: _searchController,
              onChanged: (val) =>
                  ref.read(conversationsProvider.notifier).searchUsers(val),
              style: const TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                hintText: "Search conversations...",
                hintStyle: const TextStyle(color: AppTheme.textSecondary),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppTheme.textSecondary,
                ),
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

          // 2. UNIFIED LIST
          Expanded(
            child: convState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : convState.conversations.isEmpty
                ? const Center(child: Text("No chats found"))
                : ListView.builder(
                    itemCount: convState.conversations.length,
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

  // Separate Widget for cleaner code
  Widget _buildConversationTile(Conversation conv) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
        // ✅ Uses the enhanced helper (Deleted > Audio > Image > Text)
        subtitle: _buildLastMessagePreview(conv),
        onTap: () => _joinChat(conv),
      ),
    );
  }

  // ✅ Helper to format the last message preview
  Widget _buildLastMessagePreview(Conversation conv) {
    // 1. Check for DELETED message first (Priority 1)
    if (conv.lastMessageIsDeleted) {
      return Row(
        children: [
          const Icon(Icons.block, size: 16, color: Colors.grey),
          const SizedBox(width: 4),
          const Text(
            "This message was deleted",
            style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic),
          ),
        ],
      );
    }

    // 2. Check for Voice Message
    final bool isAudio =
        conv.lastMessage.contains('/video/upload/') ||
        conv.lastMessage.endsWith('.m4a') ||
        conv.lastMessage.endsWith('.mp3');

    if (isAudio) {
      return Row(
        children: [
          const Icon(Icons.mic, size: 16, color: AppTheme.primary),
          const SizedBox(width: 4),
          const Text("Voice Message", style: TextStyle(color: Colors.grey)),
        ],
      );
    }

    // 3. Check for Photo
    final bool isImage =
        conv.lastMessage.contains('📷 Photo') ||
        conv.lastMessage.contains('📷 Image') ||
        conv.lastMessage.endsWith('.jpg') ||
        conv.lastMessage.endsWith('.png') ||
        conv.lastMessage.endsWith('.webp');

    if (isImage) {
      return Row(
        children: [
          const Icon(Icons.photo, size: 16, color: AppTheme.primary),
          const SizedBox(width: 4),
          const Text("Photo", style: TextStyle(color: Colors.grey)),
        ],
      );
    }

    // 4. If raw E2E ciphertext leaked through (decryption couldn't happen),
    //    show a lock icon so the UI doesn't display raw gibberish.
    if (conv.lastMessage.startsWith('e2e:v1:')) {
      return Row(
        children: const [
          Icon(Icons.lock_outline, size: 16, color: AppTheme.primary),
          SizedBox(width: 4),
          Text('Message', style: TextStyle(color: Colors.grey)),
        ],
      );
    }

    // 5. Default: show the decrypted text preview
    return Text(
      conv.lastMessage,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.subTitleStyle,
    );
  }

  /// Cached avatar with disk persistence — works offline after first load.
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
