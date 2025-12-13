import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../providers/socket_provider.dart';
import '../services/auth_service.dart'; // Import this to use search
import 'chat_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<dynamic> _conversations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadConversations();
  }

  // Fetch the "Inbox"
  Future<void> _loadConversations() async {
    // FIX: Ensure widget is alive before using 'ref'
    if (!mounted) return;

    final user = ref.read(authProvider).user;
    if (user == null) return;

    final chats = await ref.read(authServiceProvider).getConversations(user.id);

    // FIX: Check mounted again before calling setState
    if (mounted) {
      setState(() {
        _conversations = chats;
        _isLoading = false;
      });
    }
  }

  // Show a popup to search for a new user
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

              // 1. Search API
              final result = await ref
                  .read(authServiceProvider)
                  .searchUser(username);
              Navigator.pop(context); // Close dialog

              if (result != null) {
                // 2. Found! Open Chat
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
    // Check if we are trying to chat with ourselves
    final myUser = ref.read(authProvider).user;
    if (targetUser['_id'] == myUser?.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You can't chat with yourself!")),
      );
      return;
    }

    final socket = ref.read(socketServiceProvider).socket;

    // 1. Request Private Chat
    socket.emit('join_private_chat', targetUser['_id']);

    // 2. Wait for Room Ready
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
      ).then((_) => _loadConversations()); // Refresh list when coming back
    });
  }

  @override
  Widget build(BuildContext context) {
    // We get the user, and now we will USE it below
    final currentUser = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(
        // FIX: Display the username dynamically
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

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Colors.grey.shade300,
                    child: const Icon(Icons.person, color: Colors.white),
                  ),
                  title: Text(
                    otherUser['username'] ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    chat['lastMessage'] ?? 'Start a conversation',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
