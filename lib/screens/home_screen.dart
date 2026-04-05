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
            CircleAvatar(
              radius: 28,
              backgroundColor: AppTheme.primary.withOpacity(0.2),
              backgroundImage:
                  (conv.otherUserAvatar != null &&
                      conv.otherUserAvatar!.isNotEmpty)
                  ? NetworkImage(conv.otherUserAvatar!)
                  : null,
              child:
                  (conv.otherUserAvatar == null ||
                      conv.otherUserAvatar!.isEmpty)
                  ? Text(
                      conv.otherUserName.isNotEmpty
                          ? conv.otherUserName[0].toUpperCase()
                          : "?",
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
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
        conv.lastMessage.contains('/image/upload/') ||
        conv.lastMessage.endsWith('.jpg') ||
        conv.lastMessage.endsWith('.png');

    if (isImage) {
      return Row(
        children: [
          const Icon(Icons.photo, size: 16, color: AppTheme.primary),
          const SizedBox(width: 4),
          const Text("Photo", style: TextStyle(color: Colors.grey)),
        ],
      );
    }

    if (conv.lastMessage == 'Encrypted message') {
      return Row(
        children: const [
          Icon(Icons.lock, size: 16, color: AppTheme.primary),
          SizedBox(width: 4),
          Text('Encrypted message', style: TextStyle(color: Colors.grey)),
        ],
      );
    }

    // 4. Default Text Message
    return Text(
      conv.lastMessage,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.subTitleStyle,
    );
  }
}
