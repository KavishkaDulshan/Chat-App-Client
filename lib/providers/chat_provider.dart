import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:image_picker/image_picker.dart';
import '../services/image_service.dart';
import 'auth_provider.dart';
import 'socket_provider.dart';

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

final chatProvider = NotifierProvider.autoDispose<ChatController, ChatState>(
  ChatController.new,
);

class ChatController extends Notifier<ChatState> {
  late IO.Socket _socket;
  final ImageService _imageService = ImageService();
  Timer? _typingTimer;

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

    // ✅ FIX: Attach listeners BEFORE emitting to catch the immediate response
    _attachListeners();

    // Now it is safe to ask the server
    _socket.emit('join_private_chat', otherUserId);
  }

  void _defineHandlers() {
    final myUserId = ref.read(authProvider).user?.id;

    _messageHandler = (data) {
      final incomingRoomId = data['roomId'].toString();

      // Strict check to ensure we don't show messages from other chats
      if (incomingRoomId != state.activeRoomId) return;
      if (state.messages.any((msg) => msg['_id'] == data['_id'])) return;

      state = state.copyWith(messages: [...state.messages, data]);

      if (data['sender_id'] != myUserId) {
        _socket.emit('conversation:read', {'roomId': state.activeRoomId});
      }
    };

    _historyHandler = (data) {
      final incomingRoomId = data['roomId'].toString();

      state = state.copyWith(
        activeRoomId:
            incomingRoomId, // Updates ID if server resolved a different one
        messages: List<Map<String, dynamic>>.from(data['history']),
        isLoading: false,
      );
      _socket.emit('conversation:read', {'roomId': incomingRoomId});
    };

    _typingHandler = (data) {
      if (data['username'] == ref.read(authProvider).user?.username) return;
      if (data['roomId'].toString() != state.activeRoomId) return;
      state = state.copyWith(isTyping: true, typingUser: data['username']);
    };

    _stopTypingHandler = (data) {
      if (data is Map && data['roomId'].toString() != state.activeRoomId)
        return;
      state = state.copyWith(isTyping: false);
    };

    _readAckHandler = (data) {
      final readerId = data['readerId'];
      if (data['roomId'].toString() == state.activeRoomId &&
          readerId != myUserId) {
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
      if (data['roomId'].toString() == state.activeRoomId) {
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
    // Remove first to avoid duplicates, then add
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

  void sendVoiceMessage(String audioUrl, int durationInSeconds) {
    _socket.emit('chat_message', {
      'content': audioUrl,
      'roomId': state.activeRoomId,
      'type': 'audio',
      'duration': durationInSeconds,
    });
  }
}
