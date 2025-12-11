import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/socket_provider.dart';
import '../providers/auth_provider.dart';
import 'chat_screen.dart';

class ContactScreen extends ConsumerStatefulWidget {
  const ContactScreen({super.key});

  @override
  ConsumerState<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends ConsumerState<ContactScreen> {
  List<dynamic> _users = [];

  @override
  void initState() {
    super.initState();
    // Defer socket call to next frame to ensure provider is ready
    Future.microtask(() => _setupSocket());
  }

  void _setupSocket() {
    final socket = ref.read(socketServiceProvider).socket;

    socket.emit('get_users');

    socket.on('users_list', (data) {
      if (mounted) setState(() => _users = data);
    });

    socket.on('user_status_change', (data) {
      if (mounted) {
        setState(() {
          final index = _users.indexWhere((u) => u['_id'] == data['userId']);
          if (index != -1) {
            _users[index]['is_online'] = data['isOnline'];
          }
        });
      }
    });
  }

  void _joinChat(dynamic targetUser) {
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
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(authProvider).user;

    return Scaffold(
      appBar: AppBar(
        title: Text("Contacts (${currentUser?.username})"),
        actions: [
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
      body: ListView.builder(
        itemCount: _users.length,
        itemBuilder: (context, index) {
          final user = _users[index];
          final isOnline = user['is_online'] ?? false;

          if (user['_id'] == currentUser?.id) return const SizedBox.shrink();

          return ListTile(
            leading: CircleAvatar(
              backgroundColor: isOnline ? Colors.green : Colors.grey,
              child: const Icon(Icons.person, color: Colors.white),
            ),
            title: Text(user['username']),
            subtitle: Text(isOnline ? "Online" : "Offline"),
            onTap: () => _joinChat(user),
          );
        },
      ),
    );
  }
}
