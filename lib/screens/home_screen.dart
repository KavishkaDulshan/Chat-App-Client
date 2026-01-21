import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../providers/auth_provider.dart';
import '../providers/socket_provider.dart';
import '../services/auth_service.dart';
import 'chat_screen.dart';
import '../app_theme.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/notification_service.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<dynamic> _conversations = [];
  bool _isLoading = true;
  late IO.Socket _socket;

  late Function(dynamic) _homeMessageHandler;
  late Function(dynamic) _statusHandler;

  Map<String, dynamic>? _selectedChat;

  @override
  void initState() {
    super.initState();
    // 1. Load conversations immediately on startup
    _loadConversations();
    _socket = ref.read(socketServiceProvider).socket;

    // Initialize Handlers
    _homeMessageHandler = (data) {
      if (!mounted) return;

      final myUserId = ref.read(authProvider).user?.id;
      final senderId = data['sender_id'];
      final isMe = senderId == myUserId;

      if (!isMe && !kIsWeb && Platform.isWindows) {
        NotificationService().showLocalNotification(
          data['sender_name'] ?? "New Message",
          data['content'] ?? "You have a new message",
        );
      }

      // Acknowledge
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
          updatedChat['updatedAt'] = data['timestamp'];
          _conversations.removeAt(index);
          _conversations.insert(0, updatedChat);
        } else {
          // New Chat Logic
          if (!isMe) {
            final newChat = {
              'id': data['roomId'],
              'lastMessage': data['content'],
              'updatedAt': data['timestamp'],
              'otherUser': {
                '_id': data['sender_id'],
                'id': data['sender_id'],
                'username': data['sender_name'] ?? 'User',
                'profile_pic': data['sender_avatar'], // Handle avatar
                'is_online': true,
              },
            };
            _conversations.insert(0, newChat);
          } else {
            _loadConversations();
          }
        }
      });
    };

    _statusHandler = (data) {
      if (!mounted) return;
      setState(() {
        for (var chat in _conversations) {
          final otherUser = chat['otherUser'];
          if (otherUser != null &&
              (otherUser['_id'] == data['userId'] ||
                  otherUser['id'] == data['userId'])) {
            otherUser['is_online'] = data['isOnline'];
          }
        }
      });
    };

    Future.microtask(() => _setupSocketListeners());
  }

  void _setupSocketListeners() {
    if (!_socket.hasListeners('chat_message')) {
      _socket.on('chat_message', _homeMessageHandler);
    }
    if (!_socket.hasListeners('user_status_change')) {
      _socket.on('user_status_change', _statusHandler);
    }
  }

  @override
  void dispose() {
    _socket.off('chat_message', _homeMessageHandler);
    _socket.off('user_status_change', _statusHandler);
    super.dispose();
  }

  Future<void> _loadConversations() async {
    final user = ref.read(authProvider).user;
    if (user == null) return;

    // This call will now work because we fixed the Backend URL
    final conversations = await ref
        .read(authServiceProvider)
        .getConversations(); // Passed implicitly inside service or pass ID if needed

    if (mounted) {
      setState(() {
        _conversations = conversations;
        _isLoading = false;
      });
    }
  }

  void _joinChat(Map<String, dynamic> otherUser) {
    final myUser = ref.read(authProvider).user;
    if (myUser == null) return;

    // Robust ID extraction
    final otherUserId = otherUser['_id'] ?? otherUser['id'];

    final ids = [myUser.id, otherUserId];
    ids.sort();
    final tempRoomId = ids.join('_');

    // Notify server we are joining (important for history)
    _socket.emit('join_private_chat', otherUserId);

    final chatData = {
      'roomId': tempRoomId,
      'otherUserId': otherUserId,
      'otherUser': otherUser, // Contains username, profile_pic
    };

    if (MediaQuery.of(context).size.width > 800) {
      setState(() => _selectedChat = chatData);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            otherUserName: otherUser['username'] ?? 'User',
            otherUserId: otherUserId,
            roomId: tempRoomId,
            initialHistory: const [],
            isDesktop: false,
          ),
        ),
      ).then((_) => _loadConversations());
    }
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

              // 1. SEARCH RETURNS A LIST
              final List<dynamic> results = await ref
                  .read(authServiceProvider)
                  .searchUser(username);

              if (mounted) {
                if (results.isNotEmpty) {
                  // 2. JOIN THE FIRST RESULT (Fixes the crash)
                  _joinChat(results[0]);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("User not found")),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            child: const Text("Chat", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
                                otherUserId: _selectedChat!['otherUserId'],
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
    if (_conversations.isEmpty) {
      return Center(
        child: Text("No messages yet", style: AppTheme.subTitleStyle),
      );
    }

    return ListView.builder(
      itemCount: _conversations.length,
      padding: const EdgeInsets.symmetric(vertical: 10),
      itemBuilder: (context, index) {
        final chat = _conversations[index];
        final otherUser = chat['otherUser'];

        // Safety Check
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
                  backgroundColor: AppTheme.primary.withOpacity(0.2),
                  backgroundImage:
                      (otherUser['profile_pic'] != null &&
                          otherUser['profile_pic'] != "")
                      ? NetworkImage(otherUser['profile_pic'])
                      : null,
                  child:
                      (otherUser['profile_pic'] == null ||
                          otherUser['profile_pic'] == "")
                      ? Text(
                          (otherUser['username'] as String)[0].toUpperCase(),
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
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
