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

  // For Desktop Split View
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
      final roomId = data['roomId'];
      final content = data['content'];

      // 1. Send Delivery Ack (I received it!)
      _socket.emit('message:delivered', {
        'messageId': data['_id'],
        'roomId': roomId,
      });

      setState(() {
        final index = _conversations.indexWhere((c) => c['id'] == roomId);
        if (index != -1) {
          final chat = _conversations.removeAt(index);
          chat['lastMessage'] = content;
          chat['updatedAt'] = DateTime.now().toString();
          _conversations.insert(0, chat);
        } else {
          _loadConversations();
        }
      });
    });

    _socket.on('user_status_change', (data) {
      if (!mounted) return;
      setState(() {
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

  void _showSearchDialog() {
    final searchController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("New Chat"),
        content: TextField(
          controller: searchController,
          decoration: AppTheme.inputDecoration("Enter exact username"),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
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
            child: const Text("Search", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _joinChat(dynamic targetUser) {
    final myUser = ref.read(authProvider).user;
    if (targetUser['_id'] == myUser?.id) return;

    final socket = ref.read(socketServiceProvider).socket;
    socket.emit('join_private_chat', targetUser['_id']);

    socket.once('private_chat_ready', (data) {
      final roomId = data['roomId'];
      final history = List<Map<String, dynamic>>.from(data['history']);

      final chatObject = {
        'id': roomId,
        'otherUser': targetUser,
        'initialHistory': history,
      };

      // RESPONSIVE LOGIC
      final isDesktop = MediaQuery.of(context).size.width >= 800;

      if (isDesktop) {
        // Desktop: Update selected chat (Right side updates automatically)
        setState(() {
          _selectedChat = chatObject;
        });
        _loadConversations(); // Refresh list order
      } else {
        // Mobile: Push new screen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(
              otherUserName: targetUser['username'],
              roomId: roomId,
              initialHistory: history,
            ),
          ),
        ).then((_) => _loadConversations());
      }
    });
  }

  @override
  void dispose() {
    _socket.off('chat_message');
    _socket.off('user_status_change');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // LAYOUT BUILDER: Check screen width
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 800;

        return Scaffold(
          backgroundColor: Colors.white, // Split view background
          body: Row(
            children: [
              // 1. LEFT SIDE (Chat List)
              // On Mobile: Takes full width. On Desktop: Takes 350px or 30%.
              Expanded(
                flex: isDesktop ? 3 : 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: isDesktop
                        ? Border(right: BorderSide(color: Colors.grey.shade200))
                        : null,
                  ),
                  child: Column(
                    children: [
                      _buildAppBar(context),
                      Expanded(
                        child: _isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : _conversations.isEmpty
                            ? const Center(child: Text("No chats yet"))
                            : ListView.builder(
                                itemCount: _conversations.length,
                                itemBuilder: (context, index) {
                                  final chat = _conversations[index];
                                  return _buildChatTile(chat, isDesktop);
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),

              // 2. RIGHT SIDE (Active Chat) - DESKTOP ONLY
              if (isDesktop)
                Expanded(
                  flex: 7,
                  child: _selectedChat == null
                      ? Container(
                          color: AppTheme.background,
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat,
                                  size: 80,
                                  color: Colors.black12,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  "Select a chat to start messaging",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ChatScreen(
                          // Key is crucial! It forces the widget to rebuild when switching chats
                          key: ValueKey(_selectedChat!['id']),
                          otherUserName:
                              _selectedChat!['otherUser']['username'],
                          roomId: _selectedChat!['id'],
                          initialHistory:
                              _selectedChat!['initialHistory'] ?? [],
                          isDesktop: true, // Optional flag for styling
                        ),
                ),
            ],
          ),
          floatingActionButton: isDesktop
              ? null
              : FloatingActionButton(
                  backgroundColor: AppTheme.primary,
                  onPressed: _showSearchDialog,
                  child: const Icon(Icons.add, color: Colors.white),
                ),
        );
      },
    );
  }

  // Helper: Custom App Bar logic
  Widget _buildAppBar(BuildContext context) {
    final user = ref.watch(authProvider).user;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Chats", style: AppTheme.headerStyle),
              Text(user?.username ?? "", style: AppTheme.subTitleStyle),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.search, color: AppTheme.textPrimary),
                onPressed: _showSearchDialog,
              ),
              IconButton(
                icon: const Icon(Icons.logout, color: Colors.redAccent),
                onPressed: () {
                  ref.read(authProvider.notifier).logout();
                  ref.read(socketServiceProvider).disconnect();
                  Navigator.pop(context); // Go back to Login
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Helper: Chat List Item
  Widget _buildChatTile(dynamic chat, bool isDesktop) {
    final otherUser = chat['otherUser'];
    final isOnline = otherUser['is_online'] ?? false;
    final isSelected = isDesktop && _selectedChat?['id'] == chat['id'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.secondary.withOpacity(0.5)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: isSelected
                  ? AppTheme.primary
                  : Colors.grey.shade200,
              child: Text(
                otherUser['username'][0].toUpperCase(),
                style: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (isOnline)
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
          style: TextStyle(
            color: isSelected ? AppTheme.primary : AppTheme.textSecondary,
            fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
        onTap: () => _joinChat(otherUser),
      ),
    );
  }
}
