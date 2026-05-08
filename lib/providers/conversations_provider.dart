import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversation.dart';
import '../services/auth_service.dart';
import '../services/e2ee_service.dart';
import '../services/local_db/database.dart';
import '../providers/socket_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/local_db_provider.dart';
import '../providers/chat_provider.dart';

// Cache for peer public keys to avoid redundant API calls
final _peerKeyCache = <String, String>{};

class ConversationState {
  final List<Conversation> conversations;
  final bool isLoading;

  ConversationState({this.conversations = const [], this.isLoading = true});

  ConversationState copyWith({
    List<Conversation>? conversations,
    bool? isLoading,
  }) {
    return ConversationState(
      conversations: conversations ?? this.conversations,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

// THE PROVIDER DEFINITION
final conversationsProvider =
    NotifierProvider<ConversationsNotifier, ConversationState>(
      ConversationsNotifier.new,
    );

// THE LOGIC CLASS
class ConversationsNotifier extends Notifier<ConversationState> {
  bool _isListening = false;
  // Track last server load time to avoid excessive reloads
  DateTime? _lastLoadTime;

  bool _isE2EMessage(String? content) {
    return content != null && content.startsWith('e2e:v1:');
  }

  @override
  ConversationState build() {
    return ConversationState();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helper: fetch and cache a peer's public E2E key
  // ──────────────────────────────────────────────────────────────────────────
  Future<String?> _getPeerPublicKey(String peerUserId) async {
    if (_peerKeyCache.containsKey(peerUserId)) {
      return _peerKeyCache[peerUserId];
    }
    final key =
        await ref.read(authServiceProvider).getUserE2EEPublicKey(peerUserId);
    if (key != null && key.isNotEmpty) {
      _peerKeyCache[peerUserId] = key;
    }
    return key;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helper: decrypt an E2E message preview — returns null on failure.
  // ──────────────────────────────────────────────────────────────────────────
  Future<String?> _tryDecryptPreview({
    required String ciphertext,
    required String myUserId,
    required String peerUserId,
  }) async {
    try {
      final peerKey = await _getPeerPublicKey(peerUserId);
      if (peerKey == null || peerKey.isEmpty) return null;

      final decrypted = await ref.read(e2eeServiceProvider).decryptTextMessage(
        encryptedPayload: ciphertext,
        myUserId: myUserId,
        peerUserId: peerUserId,
        peerPublicKeyB64: peerKey,
      );
      return (decrypted != null && decrypted.isNotEmpty) ? decrypted : null;
    } catch (_) {
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 1. Load History — Cache-first, non-blocking refresh
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> loadChats({bool forceRefresh = false}) async {
    // Avoid redundant refreshes — if loaded recently and not forced, skip
    final now = DateTime.now();
    if (!forceRefresh &&
        _lastLoadTime != null &&
        now.difference(_lastLoadTime!).inSeconds < 15 &&
        state.conversations.isNotEmpty) {
      _setupSocketListeners();
      return;
    }

    List<Conversation> cachedSnapshot = [];

    try {
      // ── Cache-first: show local data instantly ──
      final db = ref.read(localDbProvider);
      if (db != null && state.conversations.isEmpty) {
        try {
          final cached = await db.getAllConversations();
          if (cached.isNotEmpty) {
            cachedSnapshot = cached.map(_cachedConversationToModel).toList();
            // Show cached data immediately — isLoading stays false so no spinner
            state = ConversationState(
              conversations: cachedSnapshot,
              isLoading: false,
            );
          }
        } catch (e) {
          print('Conv cache read error: $e');
        }
      } else {
        cachedSnapshot = List.from(state.conversations);
      }

      // ── Fetch fresh data from server in background ──
      final rawData = await ref.read(authServiceProvider).getConversations();

      if (rawData.isEmpty && cachedSnapshot.isNotEmpty) {
        // Network likely offline — keep cached data
        _setupSocketListeners();
        return;
      }

      List<Conversation> serverList = rawData
          .map((item) => Conversation.fromHistory(item as Map<String, dynamic>))
          .toList();

      // ── Decrypt E2E previews ──
      final myUserId = ref.read(authProvider).user?.id;
      if (myUserId != null) {
        serverList = await Future.wait(
          serverList.map((conv) async {
            if (conv.lastMessageIsEncrypted && !conv.lastMessageIsDeleted) {
              final decrypted = await _tryDecryptPreview(
                ciphertext: conv.lastMessage,
                myUserId: myUserId,
                peerUserId: conv.otherUserId,
              );
              if (decrypted != null) {
                return conv.copyWith(
                  lastMessage: decrypted,
                  lastMessageIsEncrypted: false,
                );
              }
            }
            return conv;
          }),
        );
      }

      // ── MERGE: keep any socket-added conversations not yet in server data ──
      final serverOtherUserIds = serverList.map((c) => c.otherUserId).toSet();
      final socketOnlyConvs = state.conversations
          .where((c) => !serverOtherUserIds.contains(c.otherUserId))
          .toList();

      final merged = [...socketOnlyConvs, ...serverList];

      _lastLoadTime = now;
      state = ConversationState(
        conversations: _deduplicate(merged),
        isLoading: false,
      );

      _cacheConversations(serverList);
      _setupSocketListeners();
    } catch (e) {
      print("Load Chats Error: $e");
      final fallback =
          state.conversations.isNotEmpty ? state.conversations : cachedSnapshot;
      state = ConversationState(
        conversations: fallback,
        isLoading: false,
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // 2. Load Search Results
  // ──────────────────────────────────────────────────────────────────────────
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

  // ──────────────────────────────────────────────────────────────────────────
  // 3. Socket Logic — IMMEDIATE updates, decrypt in background
  // ──────────────────────────────────────────────────────────────────────────
  void _setupSocketListeners() {
    if (_isListening) return;

    final socket = ref.read(socketServiceProvider).socket;

    // A. Handle Incoming Message — NO await, update immediately
    socket.on('chat_message', (data) {
      final myId = ref.read(authProvider).user?.id;
      if (myId == null) return;

      final senderId = data['sender_id'].toString();
      final roomId = data['roomId'].toString();
      final rawContent = (data['content'] ?? 'Sent a message').toString();
      final type = data['type']?.toString();

      // Determine preview text immediately (no async)
      String content;
      if (type == 'image') {
        content = '📷 Photo';
      } else if (type == 'audio') {
        content = '🎤 Voice Message';
      } else if (_isE2EMessage(rawContent)) {
        // Show placeholder immediately — will decrypt in background below
        content = '💬 Message';
      } else {
        content = rawContent;
      }

      // --- Determine the peer userId ---
      String targetOtherUserId = '';
      if (senderId == myId) {
        final indexById = state.conversations.indexWhere((c) => c.id == roomId);
        if (indexById != -1) {
          targetOtherUserId = state.conversations[indexById].otherUserId;
        } else {
          final peerIdFromPayload = data['receiver_id']?.toString() ?? '';
          if (peerIdFromPayload.isNotEmpty) {
            targetOtherUserId = peerIdFromPayload;
          } else {
            // Unknown room — do a background refresh
            Future.microtask(() => loadChats(forceRefresh: true));
            return;
          }
        }
      } else {
        targetOtherUserId = senderId;
      }

      _applyMessageToList(
        roomId: roomId,
        targetOtherUserId: targetOtherUserId,
        content: content,
        data: data,
        senderId: senderId,
        myId: myId,
      );

      // --- Background decrypt for E2E text messages ---
      if (type == 'text' && _isE2EMessage(rawContent)) {
        _decryptAndUpdatePreview(
          roomId: roomId,
          rawContent: rawContent,
          myId: myId,
          peerUserId: targetOtherUserId,
        );
      }
    });

    // B. Handle Online Status
    socket.on('user_status_change', (data) {
      final updated = state.conversations.map((c) {
        if (c.otherUserId == data['userId']) {
          return c.copyWith(isOnline: data['isOnline']);
        }
        return c;
      }).toList();
      state = ConversationState(conversations: updated, isLoading: false);
    });

    _isListening = true;
  }

  /// Apply a new/updated message to the conversation list immediately.
  void _applyMessageToList({
    required String roomId,
    required String targetOtherUserId,
    required String content,
    required Map data,
    required String senderId,
    required String myId,
  }) {
    final currentList = List<Conversation>.from(state.conversations);

    final index = currentList.indexWhere(
      (c) => c.otherUserId == targetOtherUserId,
    );
    Conversation? existingConv;
    if (index != -1) {
      existingConv = currentList.removeAt(index);
    }

    int currentUnreadCount = existingConv?.unreadCount ?? 0;
    
    // Check if we are currently inside this room
    final activeRoomId = ref.read(chatProvider).activeRoomId;
    final isCurrentlyInRoom = activeRoomId.isNotEmpty && 
        (activeRoomId == roomId || activeRoomId.contains(targetOtherUserId));
        
    if (senderId != myId && !isCurrentlyInRoom) {
      currentUnreadCount += 1;
    } else if (isCurrentlyInRoom) {
      currentUnreadCount = 0;
    }

    Conversation updatedConv;
    if (existingConv != null) {
      // Update room ID if it changed (temp → real MongoDB ID)
      if (existingConv.id != roomId && roomId.isNotEmpty) {
        updatedConv = Conversation(
          id: roomId,
          otherUserId: existingConv.otherUserId,
          otherUserName: existingConv.otherUserName,
          otherUserAvatar: existingConv.otherUserAvatar,
          isOnline: existingConv.isOnline,
          lastMessage: content,
          lastMessageIsEncrypted: false,
          updatedAt: DateTime.now(),
          unreadCount: currentUnreadCount,
        );
      } else {
        updatedConv = existingConv.copyWith(
          lastMessage: content,
          lastMessageIsEncrypted: false,
          time: DateTime.now(),
          unreadCount: currentUnreadCount,
        );
      }
    } else {
      // Brand-new conversation
      if (senderId == myId) {
        updatedConv = Conversation(
          id: roomId,
          otherUserId: targetOtherUserId,
          otherUserName: data['receiver_name'] ?? 'User',
          otherUserAvatar: data['receiver_avatar']?.toString(),
          lastMessage: content,
          updatedAt: DateTime.now(),
          isOnline: true,
          unreadCount: currentUnreadCount,
        );
      } else {
        updatedConv = Conversation(
          id: roomId,
          otherUserId: senderId,
          otherUserName: data['sender_name'] ?? 'User',
          otherUserAvatar: data['sender_avatar']?.toString(),
          lastMessage: content,
          updatedAt: DateTime.now(),
          isOnline: true,
          unreadCount: currentUnreadCount,
        );
      }
    }

    currentList.insert(0, updatedConv);
    state = ConversationState(
      conversations: _deduplicate(currentList),
      isLoading: false,
    );

    // Update local cache
    if (updatedConv.id.isNotEmpty) {
      final db = ref.read(localDbProvider);
      db?.updateConversationLastMessage(
        conversationId: updatedConv.id,
        lastMessage: content,
        lastMessageType: 'text',
        lastMessageIsDeleted: false,
        updatedAt: DateTime.now(),
      );
    }
  }

  /// Decrypt E2E preview in background and update the conversation list entry.
  Future<void> _decryptAndUpdatePreview({
    required String roomId,
    required String rawContent,
    required String myId,
    required String peerUserId,
  }) async {
    if (peerUserId.isEmpty) return;
    final decrypted = await _tryDecryptPreview(
      ciphertext: rawContent,
      myUserId: myId,
      peerUserId: peerUserId,
    );
    if (decrypted == null) return;

    // Find the conversation and update its preview
    final currentList = List<Conversation>.from(state.conversations);
    final idx = currentList.indexWhere((c) => c.id == roomId || c.otherUserId == peerUserId);
    if (idx == -1) return;

    currentList[idx] = currentList[idx].copyWith(
      lastMessage: decrypted,
      lastMessageIsEncrypted: false,
    );
    state = ConversationState(
      conversations: currentList,
      isLoading: false,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Helper: find the peer userId for a given roomId from current state
  // ──────────────────────────────────────────────────────────────────────────
  String? _findPeerForRoom(String roomId) {
    final conv = state.conversations.firstWhere(
      (c) => c.id == roomId,
      orElse: () => Conversation(
        id: '',
        otherUserId: '',
        otherUserName: '',
        lastMessage: '',
      ),
    );
    return conv.otherUserId.isNotEmpty ? conv.otherUserId : null;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // HELPER: STRICT DEDUPLICATION
  // ──────────────────────────────────────────────────────────────────────────
  List<Conversation> _deduplicate(List<Conversation> input) {
    final seen = <String>{};
    return input.where((conv) {
      if (seen.contains(conv.otherUserId)) return false;
      seen.add(conv.otherUserId);
      return true;
    }).toList();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LOCAL DB CACHE HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  void _cacheConversations(List<Conversation> conversations) {
    final db = ref.read(localDbProvider);
    if (db == null) return;
    try {
      final companions = conversations
          .where((c) => c.id.isNotEmpty)
          .map((c) => CachedConversationsCompanion.insert(
                id: c.id,
                otherUserId: c.otherUserId,
                otherUserName: Value(c.otherUserName),
                otherUserAvatar: Value(c.otherUserAvatar),
                lastMessage: Value(c.lastMessage),
                lastMessageType: const Value('text'),
                lastMessageIsDeleted: Value(c.lastMessageIsDeleted),
                updatedAt: Value(c.updatedAt),
              ))
          .toList();
      if (companions.isNotEmpty) {
        db.upsertConversations(companions);
      }
    } catch (e) {
      print('Conv cache write error: $e');
    }
  }

  Conversation _cachedConversationToModel(CachedConversation c) {
    return Conversation(
      id: c.id,
      otherUserId: c.otherUserId,
      otherUserName: c.otherUserName,
      otherUserAvatar: c.otherUserAvatar,
      lastMessage: c.lastMessage,
      lastMessageIsDeleted: c.lastMessageIsDeleted,
      updatedAt: c.updatedAt,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CONTACT STATUS UPDATER (For real-time UI)
  // ──────────────────────────────────────────────────────────────────────────
  void updateContactStatus(String userId, String contactStatus) {
    final index = state.conversations.indexWhere((c) => c.otherUserId == userId);
    if (index != -1) {
      final updatedList = List<Conversation>.from(state.conversations);
      updatedList[index] = updatedList[index].copyWith(contactStatus: contactStatus);
      state = state.copyWith(conversations: updatedList);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // RESET UNREAD COUNT
  // ──────────────────────────────────────────────────────────────────────────
  void resetUnreadCount(String roomId) {
    final index = state.conversations.indexWhere((c) => c.id == roomId || c.otherUserId == roomId);
    if (index != -1) {
      final updatedList = List<Conversation>.from(state.conversations);
      updatedList[index] = updatedList[index].copyWith(unreadCount: 0);
      state = state.copyWith(conversations: updatedList);
    }
  }
}
