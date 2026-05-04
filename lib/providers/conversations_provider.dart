import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/conversation.dart';
import '../services/auth_service.dart';
import '../services/e2ee_service.dart';
import '../services/local_db/database.dart';
import '../providers/socket_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/local_db_provider.dart';

// Cache for peer public keys to avoid redundant API calls
final _peerKeyCache = <String, String>{};

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
  // Helper: decrypt an E2E message preview for the conversation list.
  // Returns the decrypted text, or null if decryption fails.
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
  // 1. Load History (Default) — Cache-first
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> loadChats() async {
    // Snapshot cached conversations before any server call,
    // so we can fall back to them if the server is unreachable.
    List<Conversation> cachedSnapshot = [];

    try {
      // ── Cache-first: show local data instantly ──
      final db = ref.read(localDbProvider);
      if (db != null && state.conversations.isEmpty) {
        try {
          final cached = await db.getAllConversations();
          if (cached.isNotEmpty) {
            cachedSnapshot = cached.map(_cachedConversationToModel).toList();
            state = ConversationState(
              conversations: cachedSnapshot,
              isLoading: true, // still fetching from server
            );
          } else {
            state = ConversationState(conversations: [], isLoading: true);
          }
        } catch (e) {
          print('Conv cache read error: $e');
          state = ConversationState(conversations: [], isLoading: true);
        }
      } else if (state.conversations.isEmpty) {
        state = ConversationState(conversations: [], isLoading: true);
      } else {
        // Already have data from a previous load — keep it as snapshot
        cachedSnapshot = List.from(state.conversations);
      }

      // ── Fetch fresh data from server ──
      final rawData = await ref.read(authServiceProvider).getConversations();

      // ── KEY FIX: getConversations() returns [] BOTH when server says
      // "no conversations" AND when the network call fails (it swallows
      // errors). If we have cached data and server returned empty, keep
      // the cached data — the user is likely offline. ──
      if (rawData.isEmpty && cachedSnapshot.isNotEmpty) {
        state = ConversationState(
          conversations: cachedSnapshot,
          isLoading: false,
        );
        _setupSocketListeners();
        return;
      }

      List<Conversation> cleanList = rawData
          .map((item) => Conversation.fromHistory(item as Map<String, dynamic>))
          .toList();

      // ✅ Decrypt E2E-encrypted last-message previews on the client
      final myUserId = ref.read(authProvider).user?.id;
      if (myUserId != null) {
        cleanList = await Future.wait(
          cleanList.map((conv) async {
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

      state = ConversationState(
        conversations: _deduplicate(cleanList),
        isLoading: false,
      );

      // ── Write server data to local cache ──
      _cacheConversations(cleanList);

      _setupSocketListeners();
    } catch (e) {
      print("Load Chats Error: $e");
      // If server fetch fails but we have cached data, keep showing it
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
  // 3. Socket Logic
  // ──────────────────────────────────────────────────────────────────────────
  void _setupSocketListeners() {
    if (_isListening) return;

    final socket = ref.read(socketServiceProvider).socket;

    // A. Handle Incoming Message
    socket.on('chat_message', (data) async {
      final myId = ref.read(authProvider).user?.id;
      if (myId == null) return;

      final senderId = data['sender_id'].toString();
      final roomId = data['roomId'].toString();
      final rawContent = (data['content'] ?? "Sent a message").toString();

      // ✅ Decrypt E2E previews in real-time
      String content = rawContent;
      if (_isE2EMessage(rawContent)) {
        final peerUserId = (senderId == myId)
            ? _findPeerForRoom(roomId)
            : senderId;

        if (peerUserId != null && peerUserId.isNotEmpty) {
          final decrypted = await _tryDecryptPreview(
            ciphertext: rawContent,
            myUserId: myId,
            peerUserId: peerUserId,
          );
          if (decrypted != null) {
            content = decrypted;
          }
          // If decryption fails, content stays as raw ciphertext — UI handles
        }
      }

      // Format media messages for preview
      final type = data['type']?.toString();
      if (type == 'image') {
        content = '📷 Photo';
      } else if (type == 'audio') {
        content = '🎤 Voice Message';
      }

      // Create a modifiable copy
      final List<Conversation> currentList = List.from(state.conversations);

      // LOGIC: Who is the "Other Person"?
      String targetOtherUserId = '';

      if (senderId == myId) {
        // First, try to find by room ID
        final indexById = currentList.indexWhere((c) => c.id == roomId);
        if (indexById != -1) {
          targetOtherUserId = currentList[indexById].otherUserId;
        } else {
          // For brand-new conversations, the room ID is fresh from the server.
          // Try to find the conversation by peer user ID from the payload.
          final peerIdFromPayload = data['receiver_id']?.toString() ?? '';
          if (peerIdFromPayload.isNotEmpty) {
            targetOtherUserId = peerIdFromPayload;
          } else {
            // Fall back to reloading the full list from server
            loadChats();
            return;
          }
        }
      } else {
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
        updatedConv = existingConv.copyWith(
          lastMessage: content,
          lastMessageIsEncrypted: false,
          time: DateTime.now(),
        );
        // Update the room ID if it changed (e.g. temp ID → real MongoDB ID)
        if (existingConv.id != roomId && roomId.isNotEmpty) {
          updatedConv = Conversation(
            id: roomId,
            otherUserId: updatedConv.otherUserId,
            otherUserName: updatedConv.otherUserName,
            otherUserAvatar: updatedConv.otherUserAvatar,
            isOnline: updatedConv.isOnline,
            lastMessage: content,
            lastMessageIsEncrypted: false,
            updatedAt: DateTime.now(),
          );
        }
      } else {
        if (senderId == myId) {
          // Sender created a new chat — build the conversation from payload
          updatedConv = Conversation(
            id: roomId,
            otherUserId: targetOtherUserId,
            otherUserName: data['receiver_name'] ?? 'User',
            otherUserAvatar: data['receiver_avatar'],
            lastMessage: content,
            updatedAt: DateTime.now(),
            isOnline: true,
          );
        } else {
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
      }

      currentList.insert(0, updatedConv);
      state = ConversationState(
        conversations: _deduplicate(currentList),
        isLoading: false,
      );

      // Update the local cache with the new last message
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
      if (seen.contains(conv.otherUserId)) {
        return false;
      }
      seen.add(conv.otherUserId);
      return true;
    }).toList();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LOCAL DB CACHE HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  /// Fire-and-forget: write conversations to local cache.
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

  /// Convert a Drift CachedConversation → Conversation model for the UI.
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
}
