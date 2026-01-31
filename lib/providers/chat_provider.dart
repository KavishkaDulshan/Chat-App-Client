import 'dart:async';
// REMOVED: import 'dart:io';  <-- Caused Web Crash
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:image_picker/image_picker.dart'; // <-- ADDED THIS
import '../services/image_service.dart';
import '../services/socket_service.dart';
import 'auth_provider.dart';
import 'socket_provider.dart';

// --- 1. THE STATE (DATA) ---
class ChatState {
  final List<Map<String, dynamic>> messages;
  final bool isLoading;
  final bool isTyping;
  final bool isUploading;
  final String? typingUser;
  final String activeRoomId;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isTyping = false,
    this.isUploading = false,
    this.typingUser,
    this.activeRoomId = '',
  });

  ChatState copyWith({
    List<Map<String, dynamic>>? messages,
    bool? isLoading,
    bool? isTyping,
    bool? isUploading,
    String? typingUser,
    String? activeRoomId,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isTyping: isTyping ?? this.isTyping,
      isUploading: isUploading ?? this.isUploading,
      typingUser: typingUser ?? this.typingUser,
      activeRoomId: activeRoomId ?? this.activeRoomId,
    );
  }
}

// --- 2. THE PROVIDER DEFINITION ---
final chatProvider = NotifierProvider.autoDispose<ChatController, ChatState>(
  ChatController.new,
);

// --- 3. THE CONTROLLER (LOGIC) ---
class ChatController extends Notifier<ChatState> {
  late IO.Socket _socket;
  final ImageService _imageService = ImageService();
  Timer? _typingTimer;

  // Handler variables
  late Function(dynamic) _messageHandler;
  late Function(dynamic) _typingHandler;
  late Function(dynamic) _stopTypingHandler;
  late Function(dynamic) _historyHandler;
  late Function(dynamic) _readAckHandler;
  late Function(dynamic) _statusUpdateHandler;
  late Function(dynamic) _deleteHandler;

  @override
  ChatState build() {
    _socket = ref.read(socketServiceProvider).socket;

    ref.onDispose(() {
      _typingTimer?.cancel();
      _socket.off('chat_message', _messageHandler);
      _socket.off('private_chat_ready', _historyHandler);
      _socket.off('display_typing', _typingHandler);
      _socket.off('hide_typing', _stopTypingHandler);
      _socket.off('conversation:read_ack', _readAckHandler);
      _socket.off('message:status_update', _statusUpdateHandler);
      _socket.off('message:deleted', _deleteHandler);
    });

    _defineHandlers();

    return const ChatState();
  }

  // --- ACTIONS ---

  void joinChat(
    String roomId,
    String otherUserId,
    List<Map<String, dynamic>> initialHistory,
  ) {
    state = state.copyWith(
      activeRoomId: roomId,
      messages: List.from(initialHistory),
      isLoading: true,
    );

    _socket.emit('join_private_chat', otherUserId);
    _attachListeners();
  }

  void _defineHandlers() {
    final myUserId = ref.read(authProvider).user?.id;

    _messageHandler = (data) {
      if (data['roomId'] != state.activeRoomId) return;
      if (state.messages.any((msg) => msg['_id'] == data['_id'])) return;

      state = state.copyWith(messages: [...state.messages, data]);

      if (data['sender_id'] != myUserId) {
        _socket.emit('conversation:read', {'roomId': state.activeRoomId});
      }
    };

    _historyHandler = (data) {
      state = state.copyWith(
        activeRoomId: data['roomId'],
        messages: List<Map<String, dynamic>>.from(data['history']),
        isLoading: false,
      );
      _socket.emit('conversation:read', {'roomId': data['roomId']});
    };

    _typingHandler = (data) {
      if (data['username'] == ref.read(authProvider).user?.username) return;
      if (data['roomId'] != state.activeRoomId) return;
      state = state.copyWith(isTyping: true, typingUser: data['username']);
    };

    _stopTypingHandler = (data) {
      if (data is Map && data['roomId'] != state.activeRoomId) return;
      state = state.copyWith(isTyping: false);
    };

    _readAckHandler = (data) {
      final readerId = data['readerId'];
      if (data['roomId'] == state.activeRoomId && readerId != myUserId) {
        final updatedMessages = state.messages.map((msg) {
          if (msg['sender_id'] == myUserId) {
            return {...msg, 'status': 'read'};
          }
          return msg;
        }).toList();
        state = state.copyWith(messages: updatedMessages);
      }
    };

    _statusUpdateHandler = (data) {
      if (data['roomId'] == state.activeRoomId) {
        final updatedMessages = state.messages.map((msg) {
          if (msg['_id'] == data['messageId']) {
            return {...msg, 'status': data['status']};
          }
          return msg;
        }).toList();
        state = state.copyWith(messages: updatedMessages);
      }
    };

    _deleteHandler = (messageId) {
      final updatedMessages = state.messages.map((msg) {
        if (msg['_id'] == messageId) {
          return {
            ...msg,
            'isDeleted': true,
            'content': 'This message was deleted',
          };
        }
        return msg;
      }).toList();
      state = state.copyWith(messages: updatedMessages);
    };
  }

  void _attachListeners() {
    _socket.off('chat_message', _messageHandler);
    _socket.on('chat_message', _messageHandler);

    _socket.off('private_chat_ready', _historyHandler);
    _socket.on('private_chat_ready', _historyHandler);

    _socket.off('display_typing', _typingHandler);
    _socket.on('display_typing', _typingHandler);

    _socket.off('hide_typing', _stopTypingHandler);
    _socket.on('hide_typing', _stopTypingHandler);

    _socket.off('conversation:read_ack', _readAckHandler);
    _socket.on('conversation:read_ack', _readAckHandler);

    _socket.off('message:status_update', _statusUpdateHandler);
    _socket.on('message:status_update', _statusUpdateHandler);

    _socket.off('message:deleted', _deleteHandler);
    _socket.on('message:deleted', _deleteHandler);
  }

  void sendMessage(String content, {String type = 'text'}) {
    if (content.trim().isEmpty) return;

    _socket.emit('chat_message', {
      'content': content.trim(),
      'roomId': state.activeRoomId,
      'type': type,
    });
  }

  Future<void> sendImage() async {
    // UPDATED: Now uses XFile instead of File
    final XFile? file = await _imageService.pickImage();
    if (file == null) return;

    state = state.copyWith(isUploading: true);
    final String? imageUrl = await _imageService.uploadImage(file);
    state = state.copyWith(isUploading: false);

    if (imageUrl != null) {
      sendMessage(imageUrl, type: 'image');
    }
  }

  void sendTypingEvent(String text) {
    _socket.emit('typing', state.activeRoomId);
    if (_typingTimer?.isActive ?? false) _typingTimer!.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      _socket.emit('stop_typing', state.activeRoomId);
    });
  }

  void deleteMessage(String messageId) {
    _socket.emit('message:delete', {
      'messageId': messageId,
      'roomId': state.activeRoomId,
    });
  }
}
