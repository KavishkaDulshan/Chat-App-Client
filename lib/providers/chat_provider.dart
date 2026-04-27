import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../services/auth_service.dart';
import '../services/e2ee_service.dart';
import '../services/image_service.dart';
import 'auth_provider.dart';
import 'socket_provider.dart';

class ChatState {
  final List<Map<String, dynamic>> messages;
  final bool isLoading;
  final bool isTyping;
  final bool isUploading;
  final bool isLoadingMore;
  final bool hasMoreMessages;
  final String? typingUser;
  final String activeRoomId;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.isTyping = false,
    this.isUploading = false,
    this.isLoadingMore = false,
    this.hasMoreMessages = true,
    this.typingUser,
    this.activeRoomId = '',
  });

  ChatState copyWith({
    List<Map<String, dynamic>>? messages,
    bool? isLoading,
    bool? isTyping,
    bool? isUploading,
    bool? isLoadingMore,
    bool? hasMoreMessages,
    String? typingUser,
    String? activeRoomId,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isTyping: isTyping ?? this.isTyping,
      isUploading: isUploading ?? this.isUploading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
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

  String _activeOtherUserId = '';
  String? _peerPublicKey;
  bool _isListening = false;

  late Function(dynamic) _messageHandler;
  late Function(dynamic) _typingHandler;
  late Function(dynamic) _stopTypingHandler;
  late Function(dynamic) _historyHandler;
  late Function(dynamic) _readAckHandler;
  late Function(dynamic) _statusUpdateHandler;
  late Function(dynamic) _deleteHandler;
  late Function(dynamic) _moreMessagesHandler;

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
      _socket.off('more_messages', _moreMessagesHandler);
      _isListening = false;
    });

    _defineHandlers();

    return const ChatState();
  }

  Future<void> joinChat(
    String roomId,
    String otherUserId,
    List<Map<String, dynamic>> initialHistory,
  ) async {
    _activeOtherUserId = otherUserId;
    _peerPublicKey = await _fetchPeerPublicKey(otherUserId);

    state = state.copyWith(
      activeRoomId: roomId,
      messages: List.from(initialHistory),
      isLoading: true,
    );

    _attachListeners();
    _socket.emit('join_private_chat', otherUserId);
  }

  /// BUG-1: Load older messages (cursor-based pagination)
  Future<void> loadMoreMessages() async {
    if (state.isLoadingMore || !state.hasMoreMessages || state.messages.isEmpty) return;

    state = state.copyWith(isLoadingMore: true);

    final oldestMessageId = state.messages.first['_id'];
    if (oldestMessageId == null) {
      state = state.copyWith(isLoadingMore: false);
      return;
    }

    _socket.emit('load_more_messages', {
      'roomId': state.activeRoomId,
      'beforeId': oldestMessageId.toString(),
    });
  }

  void _defineHandlers() {
    final myUserId = ref.read(authProvider).user?.id;

    _messageHandler = (data) async {
      if (data is! Map) return;
      final incoming = Map<String, dynamic>.from(data);

      final incomingRoomId = incoming['roomId']?.toString() ?? '';
      if (incomingRoomId != state.activeRoomId) return;
      if (state.messages.any((msg) => msg['_id'] == incoming['_id'])) return;

      final hydrated = await _hydrateMessageForDisplay(incoming);
      state = state.copyWith(messages: [...state.messages, hydrated]);

      if (incoming['sender_id'] != myUserId) {
        _socket.emit('conversation:read', {'roomId': state.activeRoomId});
      }
    };

    _historyHandler = (data) async {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      final incomingRoomId = payload['roomId']?.toString() ?? '';
      final historyRaw = payload['history'];
      final hasMore = payload['hasMore'] == true;
      final historyList = historyRaw is List
          ? historyRaw
                .whereType<Map>()
                .map((entry) => Map<String, dynamic>.from(entry))
                .toList()
          : <Map<String, dynamic>>[];

      final hydratedHistory = await Future.wait(
        historyList.map(_hydrateMessageForDisplay),
      );

      state = state.copyWith(
        activeRoomId: incomingRoomId,
        messages: hydratedHistory,
        isLoading: false,
        hasMoreMessages: hasMore,
      );
      _socket.emit('conversation:read', {'roomId': incomingRoomId});
    };

    _moreMessagesHandler = (data) async {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      final incomingRoomId = payload['roomId']?.toString() ?? '';
      if (incomingRoomId != state.activeRoomId) return;

      final messagesRaw = payload['messages'];
      final hasMore = payload['hasMore'] == true;
      final messagesList = messagesRaw is List
          ? messagesRaw
                .whereType<Map>()
                .map((entry) => Map<String, dynamic>.from(entry))
                .toList()
          : <Map<String, dynamic>>[];

      final hydratedMessages = await Future.wait(
        messagesList.map(_hydrateMessageForDisplay),
      );

      state = state.copyWith(
        messages: [...hydratedMessages, ...state.messages],
        isLoadingMore: false,
        hasMoreMessages: hasMore,
      );
    };

    _typingHandler = (data) {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      if (payload['username'] == ref.read(authProvider).user?.username) return;
      if (payload['roomId'].toString() != state.activeRoomId) return;
      state = state.copyWith(isTyping: true, typingUser: payload['username']);
    };

    _stopTypingHandler = (data) {
      if (data is Map) {
        final payload = Map<String, dynamic>.from(data);
        if (payload['roomId'].toString() != state.activeRoomId) return;
      }
      state = state.copyWith(isTyping: false);
    };

    _readAckHandler = (data) {
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      final readerId = payload['readerId'];
      if (payload['roomId'].toString() == state.activeRoomId &&
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
      if (data is! Map) return;
      final payload = Map<String, dynamic>.from(data);
      if (payload['roomId'].toString() == state.activeRoomId) {
        final updatedMessages = state.messages.map((msg) {
          if (msg['_id'] == payload['messageId']) {
            return {...msg, 'status': payload['status']};
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
    // BUG-3: Guard against duplicate listener registration
    if (_isListening) return;

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

    _socket.off('more_messages', _moreMessagesHandler);
    _socket.on('more_messages', _moreMessagesHandler);

    _isListening = true;
  }

  Future<void> sendMessage(String content, {String type = 'text'}) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;

    var payloadContent = trimmed;

    if (type == 'text') {
      final myUser = ref.read(authProvider).user;
      if (myUser != null && _activeOtherUserId.isNotEmpty) {
        final peerKey = await _resolvePeerPublicKey();
        if (peerKey != null && peerKey.isNotEmpty) {
          try {
            payloadContent = await ref
                .read(e2eeServiceProvider)
                .encryptTextMessage(
                  plainText: trimmed,
                  myUserId: myUser.id,
                  peerUserId: _activeOtherUserId,
                  peerPublicKeyB64: peerKey,
                );
          } catch (e) {
            print('E2EE Encrypt Warning: $e');
          }
        }
      }
    }

    _socket.emit('chat_message', {
      'content': payloadContent,
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
      await sendMessage(imageUrl, type: 'image');
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

  /// BUG-4: Show friendly placeholder for undecryptable E2EE messages
  Future<Map<String, dynamic>> _hydrateMessageForDisplay(
    Map<String, dynamic> message,
  ) async {
    final isDeleted = message['isDeleted'] == true;
    final type = (message['type'] ?? 'text').toString();
    final content = (message['content'] ?? '').toString();

    if (isDeleted || type != 'text') {
      return message;
    }

    final e2ee = ref.read(e2eeServiceProvider);
    if (!e2ee.isE2EMessage(content)) {
      return message;
    }

    final myUserId = ref.read(authProvider).user?.id;
    if (myUserId == null || _activeOtherUserId.isEmpty) {
      // Cannot decrypt without identity — show friendly placeholder
      return {...message, 'content': '🔒 Encrypted message'};
    }

    final peerKey = await _resolvePeerPublicKey();
    if (peerKey == null || peerKey.isEmpty) {
      // No peer key — show friendly placeholder
      return {...message, 'content': '🔒 Encrypted message'};
    }

    try {
      final decrypted = await e2ee.decryptTextMessage(
        encryptedPayload: content,
        myUserId: myUserId,
        peerUserId: _activeOtherUserId,
        peerPublicKeyB64: peerKey,
      );

      if (decrypted != null && decrypted.isNotEmpty) {
        return {...message, 'content': decrypted};
      }
      // Null/empty result — show friendly placeholder
      return {...message, 'content': '🔒 Encrypted message'};
    } catch (_) {
      // Decryption failed — show friendly placeholder instead of gibberish
      return {...message, 'content': '🔒 Encrypted message'};
    }
  }

  Future<String?> _resolvePeerPublicKey() async {
    if (_peerPublicKey != null && _peerPublicKey!.isNotEmpty) {
      return _peerPublicKey;
    }

    if (_activeOtherUserId.isEmpty) return null;

    _peerPublicKey = await _fetchPeerPublicKey(_activeOtherUserId);
    return _peerPublicKey;
  }

  Future<String?> _fetchPeerPublicKey(String userId) async {
    try {
      return ref.read(authServiceProvider).getUserE2EEPublicKey(userId);
    } catch (e) {
      print('E2EE Peer Key Fetch Warning: $e');
      return null;
    }
  }
}
