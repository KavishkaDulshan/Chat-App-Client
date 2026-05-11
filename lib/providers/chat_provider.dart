import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

import '../services/audio_service.dart';
import '../services/auth_service.dart';
import '../services/e2ee_service.dart';
import '../services/image_service.dart';
import '../services/local_db/database.dart';
import 'auth_provider.dart';
import 'local_db_provider.dart';
import 'socket_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

final chatProvider = NotifierProvider<ChatController, ChatState>(
  ChatController.new,
);

class ChatController extends Notifier<ChatState> {
  late IO.Socket _socket;
  final ImageService _imageService = ImageService();
  Timer? _typingTimer;

  String _activeOtherUserId = '';
  String? _peerPublicKey;
  bool _isListening = false;

  bool _isE2EContent(String content) => content.startsWith('e2e:v1:');

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

    // ── Show loading state immediately ──
    state = state.copyWith(
      activeRoomId: roomId,
      messages: const [],
      isLoading: true,
    );

    // ── Load cached messages instantly (already decrypted from last session) ──
    final db = ref.read(localDbProvider);
    if (db != null) {
      try {
        final cached = await db.getMessages(roomId);
        if (cached.isNotEmpty) {
          final cachedMaps = cached.map(_cachedMessageToMap).toList();
          state = state.copyWith(
            activeRoomId: roomId,
            messages: cachedMaps,
            isLoading: false, // Show cached data immediately — no spinner
          );
        }
      } catch (e) {
        print('Cache read error: $e');
      }
    }

    // ── Fetch peer key in parallel (don't block showing cache) ──
    _fetchPeerPublicKey(otherUserId).then((key) {
      _peerPublicKey = key;
    });

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

      // Show immediately with optimistic content (no wait)
      final type = (incoming['type'] ?? 'text').toString();
      final rawContent = (incoming['content'] ?? '').toString();
      final needsDecrypt = type == 'text' && _isE2EContent(rawContent);

      if (needsDecrypt) {
        // Add immediately with placeholder, then update with decrypted
        final placeholder = {...incoming, 'content': '💬 ...' };
        state = state.copyWith(messages: [...state.messages, placeholder]);
        final hydrated = await _hydrateMessageForDisplay(incoming);
        // Replace placeholder with decrypted
        final updated = state.messages.map((m) =>
          m['_id'] == hydrated['_id'] ? hydrated : m
        ).toList();
        state = state.copyWith(messages: updated);
        _cacheMessages([hydrated], incomingRoomId);
      } else {
        final hydrated = await _hydrateMessageForDisplay(incoming);
        state = state.copyWith(messages: [...state.messages, hydrated]);
        _cacheMessages([hydrated], incomingRoomId);
      }

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

      // ── Do NOT replace cached messages with raw server ciphertext ──
      // Just update hasMore and mark loading done. Decrypt in background.
      state = state.copyWith(
        activeRoomId: incomingRoomId,
        hasMoreMessages: hasMore,
        isLoading: false,
      );

      _socket.emit('conversation:read', {'roomId': incomingRoomId});

      // Wait for peer key if not yet available (fetched in parallel in joinChat)
      if (_peerPublicKey == null && _activeOtherUserId.isNotEmpty) {
        _peerPublicKey = await _fetchPeerPublicKey(_activeOtherUserId);
      }

      // Decrypt messages SEQUENTIALLY to avoid CPU starvation on low-end devices
      final hydratedHistory = <Map<String, dynamic>>[];
      for (final msg in historyList) {
        hydratedHistory.add(await _hydrateMessageForDisplay(msg));
      }

      // Only update if still in same room
      if (state.activeRoomId == incomingRoomId) {
        state = state.copyWith(
          messages: hydratedHistory,
          isLoading: false,
        );
      }

      _cacheMessages(hydratedHistory, incomingRoomId);
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

      final hydratedMessages = <Map<String, dynamic>>[];
      for (final msg in messagesList) {
        hydratedMessages.add(await _hydrateMessageForDisplay(msg));
      }

      state = state.copyWith(
        messages: [...hydratedMessages, ...state.messages],
        isLoadingMore: false,
        hasMoreMessages: hasMore,
      );

      // Cache paginated messages
      _cacheMessages(hydratedMessages, incomingRoomId);
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
      // 1. Find the original message to check if it's media
      try {
        final oldMsg = state.messages.firstWhere((m) => m['_id'] == messageId);
        final type = oldMsg['type']?.toString();
        final content = oldMsg['content']?.toString();

        if (content != null && content.isNotEmpty && content.startsWith('http')) {
          if (type == 'image') {
            CachedNetworkImage.evictFromCache(content);
            print('🗑️ Evicted image from local cache: $content');
          } else if (type == 'audio') {
            AudioService().deleteCachedAudio(content);
            print('🗑️ Evicted audio from local cache: $content');
          }
        }
      } catch (_) {
        // Message not found in current state
      }

      // 2. Update state to reflect deletion
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

      // 3. Update local DB cache
      final db = ref.read(localDbProvider);
      db?.markMessageDeleted(messageId.toString());
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

  // ──────────────────────────────────────────────────────────────────────────
  // LOCAL DB CACHE HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  /// Fire-and-forget: upsert a list of hydrated message maps into local DB.
  void _cacheMessages(List<Map<String, dynamic>> messages, String roomId) {
    final db = ref.read(localDbProvider);
    if (db == null) return;

    try {
      final companions = messages
          .where((m) => m['_id'] != null)
          .map((m) => _mapToCompanion(m, roomId))
          .toList();
      if (companions.isNotEmpty) {
        db.upsertMessages(companions);
      }
    } catch (e) {
      print('Cache write error: $e');
    }
  }

  /// Convert a message Map (from socket/server) → Drift CachedMessagesCompanion.
  CachedMessagesCompanion _mapToCompanion(
      Map<String, dynamic> m, String roomId) {
    DateTime ts;
    try {
      ts = DateTime.parse(m['createdAt'] ?? m['timestamp'] ?? '');
    } catch (_) {
      ts = DateTime.now();
    }

    return CachedMessagesCompanion.insert(
      id: m['_id'].toString(),
      conversationId: (m['conversation_id'] ?? roomId).toString(),
      senderId: (m['sender_id'] ?? '').toString(),
      senderName: Value(
          (m['sender_name'] ?? m['senderName'] ?? 'Unknown').toString()),
      senderAvatar: Value(m['sender_avatar']?.toString()),
      content: (m['content'] ?? '').toString(),
      type: Value((m['type'] ?? 'text').toString()),
      status: Value((m['status'] ?? 'sent').toString()),
      isDeleted: Value(m['isDeleted'] == true),
      timestamp: ts,
    );
  }

  /// Convert a Drift CachedMessage object → Map for the UI layer.
  Map<String, dynamic> _cachedMessageToMap(CachedMessage m) {
    return {
      '_id': m.id,
      'conversation_id': m.conversationId,
      'sender_id': m.senderId,
      'sender_name': m.senderName,
      'sender_avatar': m.senderAvatar,
      'content': m.content,
      'type': m.type,
      'status': m.status,
      'isDeleted': m.isDeleted,
      'createdAt': m.timestamp.toIso8601String(),
    };
  }
}
