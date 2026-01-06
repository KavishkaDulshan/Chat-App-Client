import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../providers/auth_provider.dart';
import '../providers/socket_provider.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';
import '../app_theme.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<dynamic> _conversations = [];
  bool _isLoading = true;
  late IO.Socket _socket;

  Map<String, dynamic>? _selectedChat;

  @override
  void initState() {
    super.initState();
    _loadConversations();
    _socket = ref.read(socketServiceProvider).socket;
    Future.microtask(() => _setupSocketListeners());
  }

  void _setupSocketListeners() {
    if (!mounted) return;
    _socket.on('chat_message', (data) {
      if (!mounted) return;
      _socket.emit('message:delivered', {
        'messageId': data['_id'],
        'roomId': data['roomId'],
      });
      setState(() {
        final index = _conversations.indexWhere(
          (c) => c['id'] == data['roomId'],
        );
        if (index != -1) {
          final updatedChat = Map<String, dynamic>.from(_conversations[index]);
          updatedChat['lastMessage'] = data['content'];
          _conversations.removeAt(index);
          _conversations.insert(0, updatedChat);
        } else {
          _loadConversations();
        }
      });
    });
  }

  Future<void> _loadConversations() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;
    final conversations = await ref
        .read(authServiceProvider)
        .getConversations(user.id);
    if (mounted)
      setState(() {
        _conversations = conversations;
        _isLoading = false;
      });
  }

  void _joinChat(Map<String, dynamic> otherUser) {
    final myUser = ref.read(authProvider).user;
    if (myUser == null) return;

    // Temporary ID until socket resolves real one
    final ids = [myUser.id, otherUser['_id'] ?? otherUser['id']];
    ids.sort();
    final tempRoomId = ids.join('_');

    // FIX: Pass 'id' explicitly
    final otherUserId = otherUser['_id'] ?? otherUser['id'];

    final chatData = {
      'roomId': tempRoomId,
      'otherUserId': otherUserId, // Pass ID
      'otherUser': otherUser,
    };

    if (MediaQuery.of(context).size.width > 800) {
      setState(() => _selectedChat = chatData);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            otherUserName: otherUser['username'],
            otherUserId: otherUserId, // Pass ID
            roomId: tempRoomId,
            initialHistory: [],
            isDesktop: false,
          ),
        ),
      ).then((_) => _loadConversations());
    }
  }

  void _handleLogout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authProvider.notifier).logout();
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showSearchDialog() {
    final searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Search User"),
        content: TextField(
          controller: searchController,
          decoration: AppTheme.inputDecoration("Enter username"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              final username = searchController.text.trim();
              if (username.isEmpty) return;
              Navigator.pop(ctx);
              final result = await ref
                  .read(authServiceProvider)
                  .searchUser(username);
              if (result != null && mounted)
                _joinChat(result);
              else if (mounted)
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("User not found")));
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text("Chat", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text("Messages", style: AppTheme.headerStyle),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppTheme.textPrimary),
            onPressed: _showSearchDialog,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.red),
            onPressed: _handleLogout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                if (isDesktop) {
                  return Row(
                    children: [
                      SizedBox(
                        width: 350,
                        child: _buildChatList(isDesktop: true),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: _selectedChat == null
                            ? const Center(child: Text("Select a chat"))
                            : ChatScreen(
                                key: ValueKey(_selectedChat!['roomId']),
                                otherUserName:
                                    _selectedChat!['otherUser']['username'],
                                otherUserId:
                                    _selectedChat!['otherUserId'], // Pass ID
                                roomId: _selectedChat!['roomId'],
                                initialHistory: const [],
                                isDesktop: true,
                              ),
                      ),
                    ],
                  );
                } else {
                  return _buildChatList(isDesktop: false);
                }
              },
            ),
    );
  }

  Widget _buildChatList({required bool isDesktop}) {
    if (_conversations.isEmpty)
      return Center(
        child: Text("No messages yet", style: AppTheme.subTitleStyle),
      );

    return ListView.builder(
      itemCount: _conversations.length,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemBuilder: (context, index) {
        final chat = _conversations[index];
        final otherUser = chat['otherUser'];
        if (otherUser == null) return const SizedBox.shrink();
        final isSelected =
            isDesktop &&
            _selectedChat != null &&
            _selectedChat!['otherUser']['_id'] == otherUser['_id'];

        return Container(
          color: isSelected ? Colors.grey.shade100 : Colors.transparent,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            leading: Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppTheme.primary,
                  child: Text(
                    (otherUser['username'] as String)[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (otherUser['is_online'] == true)
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
            title: Text(otherUser['username'], style: AppTheme.nameStyle),
            subtitle: Text(
              chat['lastMessage'] ?? 'Start chatting',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTheme.subTitleStyle,
            ),
            onTap: () => _joinChat(otherUser),
          ),
        );
      },
    );
  }
}
