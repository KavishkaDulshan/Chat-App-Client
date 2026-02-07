import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversation.dart';
import '../services/auth_service.dart';
import '../providers/socket_provider.dart';
import '../providers/auth_provider.dart';
import '../services/notification_service.dart';

// THE STATE CLASS
class ConversationState {
  final List<Conversation> conversations;
  final bool isLoading;

  ConversationState({this.conversations = const [], this.isLoading = true});
}

// THE PROVIDER DEFINITION
final conversationsProvider =
    NotifierProvider<ConversationsNotifier, ConversationState>(
      ConversationsNotifier.new,
    );

// THE LOGIC CLASS
class ConversationsNotifier extends Notifier<ConversationState> {
  bool _isListening = false;

  @override
  ConversationState build() {
    return ConversationState();
  }

  // 1. Load History (Default)
  Future<void> loadChats() async {
    try {
      // Don't show loading spinner if we already have data (silent refresh)
      if (state.conversations.isEmpty) {
        state = ConversationState(conversations: [], isLoading: true);
      }

      final rawData = await ref.read(authServiceProvider).getConversations();

      final List<Conversation> cleanList = rawData
          .map((item) => Conversation.fromHistory(item as Map<String, dynamic>))
          .toList();

      state = ConversationState(
        conversations: _deduplicate(cleanList),
        isLoading: false,
      );
      _setupSocketListeners();
    } catch (e) {
      print("Load Chats Error: $e");
      state = ConversationState(conversations: [], isLoading: false);
    }
  }

  // 2. Load Search Results
  Future<void> searchUsers(String query) async {
    if (query.isEmpty) {
      loadChats();
      return;
    }

    state = ConversationState(conversations: [], isLoading: true);
    final rawData = await ref.read(authServiceProvider).searchUser(query);

    final List<Conversation> cleanList = rawData
        .map((item) => Conversation.fromSearch(item as Map<String, dynamic>))
        .toList();

    state = ConversationState(conversations: cleanList, isLoading: false);
  }

  // 3. Socket Logic
  void _setupSocketListeners() {
    if (_isListening) return;

    final socket = ref.read(socketServiceProvider).socket;

    // A. Handle Incoming Message
    socket.on('chat_message', (data) {
      final myId = ref.read(authProvider).user?.id;
      if (myId == null) return; // Safety check

      final senderId = data['sender_id'].toString();
      final roomId = data['roomId'].toString();
      final content = data['content'] ?? "Sent a message";

      // Create a modifiable copy
      final List<Conversation> currentList = List.from(state.conversations);

      // LOGIC: Who is the "Other Person"?
      // If I sent it, the other person is the one with whom I share this RoomID.
      // If they sent it, the other person is SenderID.
      String targetOtherUserId = '';

      if (senderId == myId) {
        // I sent this message. Find the conversation by RoomID to update it.
        final index = currentList.indexWhere((c) => c.id == roomId);
        if (index != -1) {
          targetOtherUserId = currentList[index].otherUserId;
        } else {
          // New chat I just started? I don't have the recipient's info here.
          // Must fetch from server.
          loadChats();
          return;
        }
      } else {
        // I received this message. The sender is the other person.
        targetOtherUserId = senderId;
      }

      // --- UPDATE LOGIC ---
      final index = currentList.indexWhere(
        (c) => c.otherUserId == targetOtherUserId,
      );
      Conversation? existingConv;

      if (index != -1) {
        existingConv = currentList.removeAt(index);
      }

      Conversation updatedConv;

      if (existingConv != null) {
        // Update existing chat
        updatedConv = existingConv.copyWith(
          lastMessage: content, // Fixes "Missing First Message"
          time: DateTime.now(),
        );
      } else {
        // New incoming chat (from someone else)
        if (senderId == myId) {
          return; // Should have been handled above, but double check
        }

        updatedConv = Conversation(
          id: roomId,
          otherUserId: senderId,
          otherUserName: data['sender_name'] ?? 'User',
          otherUserAvatar: data['sender_avatar'],
          lastMessage: content,
          updatedAt: DateTime.now(),
          isOnline: true,
        );
      }

      // Add to top and Deduplicate just in case
      currentList.insert(0, updatedConv);
      state = ConversationState(
        conversations: _deduplicate(currentList),
        isLoading: false,
      );

      // Notification
      if (senderId != myId && !kIsWeb && Platform.isWindows) {
        NotificationService().showLocalNotification(
          data['sender_name'] ?? "New Message",
          content,
        );
      }
    });

    // B. Handle Online Status
    socket.on('user_status_change', (data) {
      final List<Conversation> currentList = state.conversations.map((c) {
        if (c.otherUserId == data['userId']) {
          return c.copyWith(isOnline: data['isOnline']);
        }
        return c;
      }).toList();
      state = ConversationState(conversations: currentList, isLoading: false);
    });

    _isListening = true;
  }

  // --- HELPER: STRICT DEDUPLICATION ---
  // Ensures we never show two chats for the same person
  List<Conversation> _deduplicate(List<Conversation> input) {
    final seen = <String>{};
    return input.where((conv) {
      if (seen.contains(conv.otherUserId)) {
        return false; // Skip duplicate
      }
      seen.add(conv.otherUserId);
      return true;
    }).toList();
  }
}
