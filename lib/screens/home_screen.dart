import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/conversations_provider.dart'; // Import the new provider
import '../providers/socket_provider.dart';
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

  // ✅ NEW: Logout Dialog Function
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
              // Make this async
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

    // Join Room
    ref
        .read(socketServiceProvider)
        .socket
        .emit('join_private_chat', conv.otherUserId);

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
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person, color: Colors.black),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ProfileScreen()),
            ),
          ),
          // ✅ FIX: Call the dialog function instead of direct logout
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. CLEAN SEARCH BAR
          Container(
            padding: const EdgeInsets.all(16.0),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              // Delegate logic to Provider
              onChanged: (val) =>
                  ref.read(conversationsProvider.notifier).searchUsers(val),
              decoration: InputDecoration(
                hintText: "Search users...",
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: BorderSide.none,
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

                      // Look how clean this is! No if/else logic here.
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
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
        subtitle: _buildLastMessagePreview(conv),

        onTap: () => _joinChat(conv),
      ),
    );
  }

  // ✅ NEW: Helper to format the last message preview
  Widget _buildLastMessagePreview(Conversation conv) {
    // Check for Cloudinary patterns or file extensions
    // Note: Cloudinary often treats audio as "video" resource_type
    final bool isAudio =
        conv.lastMessage.contains('/video/upload/') ||
        conv.lastMessage.endsWith('.m4a') ||
        conv.lastMessage.endsWith('.mp3');

    final bool isImage =
        conv.lastMessage.contains('/image/upload/') ||
        conv.lastMessage.endsWith('.jpg') ||
        conv.lastMessage.endsWith('.png');

    if (isAudio) {
      return Row(
        children: [
          Icon(Icons.mic, size: 16, color: AppTheme.primary),
          const SizedBox(width: 4),
          const Text("Voice Message", style: TextStyle(color: Colors.grey)),
        ],
      );
    }

    if (isImage) {
      return Row(
        children: [
          Icon(Icons.photo, size: 16, color: AppTheme.primary),
          const SizedBox(width: 4),
          const Text("Photo", style: TextStyle(color: Colors.grey)),
        ],
      );
    }

    // Default Text Message
    return Text(
      conv.lastMessage,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppTheme.subTitleStyle,
    );
  }
}
