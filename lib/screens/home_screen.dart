import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../providers/auth_provider.dart';
import '../providers/socket_provider.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<dynamic> _conversations = [];
  bool _isLoading = true;
  late IO.Socket _socket; // Local variable for safe disposal

  @override
  void initState() {
    super.initState();
    // 1. Initial Data Fetch
    _loadConversations();

    // 2. Setup Real-time Listeners
    _socket = ref.read(socketServiceProvider).socket;
    Future.microtask(() => _setupSocketListeners());
  }

  void _setupSocketListeners() {
    if (!mounted) return;

    // A. Listen for Incoming Messages (To update preview text)
    _socket.on('chat_message', (data) {
      if (!mounted) return;

      final roomId = data['roomId'];
      final content = data['content'];

      setState(() {
        // 1. Find if we already have this conversation
        final index = _conversations.indexWhere((c) => c['id'] == roomId);

        if (index != -1) {
          // UPDATE EXISTING: Move to top & update text
          final chat = _conversations.removeAt(index);
          chat['lastMessage'] = content;
          chat['updatedAt'] = DateTime.now().toString(); // Update time
          _conversations.insert(0, chat); // Push to top
        } else {
          // NEW CONVERSATION: We don't have details (name, avatar) yet.
          // Simplest fix: Just reload the whole list from API.
          _loadConversations();
        }
      });
    });

    // B. Listen for Online Status Changes
    _socket.on('user_status_change', (data) {
      if (!mounted) return;

      setState(() {
        // Find any conversation with this user and update their status
        for (var chat in _conversations) {
          if (chat['otherUser']['_id'] == data['userId']) {
            chat['otherUser']['is_online'] = data['isOnline'];
          }
        }
      });
    });
  }

  Future<void> _loadConversations() async {
    if (!mounted) return;
    final user = ref.read(authProvider).user;
    if (user == null) return;

    final chats = await ref.read(authServiceProvider).getConversations(user.id);

    if (mounted) {
      setState(() {
        _conversations = chats;
        _isLoading = false;
      });
    }
  }

  // ... (Keep _showSearchDialog exactly as it was) ...
  void _showSearchDialog() {
    final searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("New Chat"),
        content: TextField(
          controller: searchController,
          decoration: const InputDecoration(hintText: "Enter exact username"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final username = searchController.text.trim();
              if (username.isEmpty) return;

              final result = await ref
                  .read(authServiceProvider)
                  .searchUser(username);
              Navigator.pop(context);

              if (result != null) {
                _joinChat(result);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("User not found!")),
                );
              }
            },
            child: const Text("Search"),
          ),
        ],
      ),
    );
  }

  void _joinChat(dynamic targetUser) {
    final myUser = ref.read(authProvider).user;
    if (targetUser['_id'] == myUser?.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't chat with yourself!")),
      );
      return;
    }

    final socket = ref.read(socketServiceProvider).socket;

    socket.emit('join_private_chat', targetUser['_id']);

    socket.once('private_chat_ready', (data) {
      final roomId = data['roomId'];
      final history = List<Map<String, dynamic>>.from(data['history']);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            otherUserName: targetUser['username'],
            roomId: roomId,
            initialHistory: history,
          ),
        ),
      ).then((_) {
        // Refresh when coming back (just in case)
        _loadConversations();
      });
    });
  }

  @override
  void dispose() {
    // CLEANUP: Stop listening to updates when this screen dies
    // (Note: In a TabView, you might NOT want to turn these off,
    // but for now this prevents errors)
    _socket.off('chat_message');
    _socket.off('user_status_change');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          currentUser != null ? "Chats (${currentUser.username})" : "Chats",
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadConversations,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              ref.read(authProvider.notifier).logout();
              ref.read(socketServiceProvider).disconnect();
              Navigator.pop(context);
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _conversations.isEmpty
          ? const Center(child: Text("No chats yet. Click + to start!"))
          : ListView.builder(
              itemCount: _conversations.length,
              itemBuilder: (context, index) {
                final chat = _conversations[index];
                final otherUser = chat['otherUser'];
                final isOnline = otherUser['is_online'] ?? false;

                return ListTile(
                  leading: Stack(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.grey.shade300,
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      // ONLINE INDICATOR
                      if (isOnline)
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
                  title: Text(
                    otherUser['username'] ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    chat['lastMessage'] ?? 'Start a conversation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      // Highlight unread messages logic could go here later
                      color: Colors.grey[600],
                    ),
                  ),
                  onTap: () => _joinChat(otherUser),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showSearchDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
