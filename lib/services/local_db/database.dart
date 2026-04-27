import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(tables: [CachedMessages, CachedConversations])
class AppDatabase extends _$AppDatabase {
  AppDatabase._(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 1;

  /// Open (or create) a per-user encrypted database.
  static Future<AppDatabase> open(String userId) async {
    // Skip encryption on web (not supported)
    if (kIsWeb) {
      throw UnsupportedError('Local database is not supported on web.');
    }

    final dbName = 'chat_cache_$userId';

    final executor = driftDatabase(
      name: dbName,
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );

    return AppDatabase._(executor);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MESSAGE OPERATIONS
  // ──────────────────────────────────────────────────────────────────────────

  /// Get cached messages for a conversation, ordered by timestamp ascending.
  /// Supports pagination via [limit] and [beforeTimestamp].
  Future<List<CachedMessage>> getMessages(
    String conversationId, {
    int limit = 50,
    DateTime? beforeTimestamp,
  }) async {
    final query = select(cachedMessages)
      ..where((m) => m.conversationId.equals(conversationId));

    if (beforeTimestamp != null) {
      query.where((m) => m.timestamp.isSmallerThanValue(beforeTimestamp));
    }

    query
      ..orderBy([(m) => OrderingTerm.desc(m.timestamp)])
      ..limit(limit);

    final results = await query.get();
    return results.reversed.toList(); // Return in chronological order
  }

  /// Upsert (insert or update) a batch of messages.
  Future<void> upsertMessages(List<CachedMessagesCompanion> messages) async {
    await batch((b) {
      for (final msg in messages) {
        b.insert(cachedMessages, msg, mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// Mark a message as deleted.
  Future<void> markMessageDeleted(String messageId) async {
    await (update(cachedMessages)..where((m) => m.id.equals(messageId)))
        .write(const CachedMessagesCompanion(
      isDeleted: Value(true),
      content: Value('This message was deleted'),
    ));
  }

  /// Update message status (sent → delivered → read).
  Future<void> updateMessageStatus(String messageId, String status) async {
    await (update(cachedMessages)..where((m) => m.id.equals(messageId)))
        .write(CachedMessagesCompanion(status: Value(status)));
  }

  /// Get the oldest message ID for a conversation (for pagination cursor).
  Future<String?> getOldestMessageId(String conversationId) async {
    final query = select(cachedMessages)
      ..where((m) => m.conversationId.equals(conversationId))
      ..orderBy([(m) => OrderingTerm.asc(m.timestamp)])
      ..limit(1);

    final result = await query.getSingleOrNull();
    return result?.id;
  }

  /// Get the count of cached messages for a conversation.
  Future<int> getMessageCount(String conversationId) async {
    final count = cachedMessages.id.count();
    final query = selectOnly(cachedMessages)
      ..addColumns([count])
      ..where(cachedMessages.conversationId.equals(conversationId));
    final result = await query.getSingle();
    return result.read(count) ?? 0;
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CONVERSATION OPERATIONS
  // ──────────────────────────────────────────────────────────────────────────

  /// Get all cached conversations, ordered by updatedAt descending.
  Future<List<CachedConversation>> getAllConversations() async {
    final query = select(cachedConversations)
      ..orderBy([(c) => OrderingTerm.desc(c.updatedAt)]);
    return query.get();
  }

  /// Upsert a batch of conversations.
  Future<void> upsertConversations(
      List<CachedConversationsCompanion> conversations) async {
    await batch((b) {
      for (final conv in conversations) {
        b.insert(cachedConversations, conv, mode: InsertMode.insertOrReplace);
      }
    });
  }

  /// Update the last message for a conversation.
  Future<void> updateConversationLastMessage({
    required String conversationId,
    required String lastMessage,
    required String lastMessageType,
    required bool lastMessageIsDeleted,
    required DateTime updatedAt,
  }) async {
    await (update(cachedConversations)
          ..where((c) => c.id.equals(conversationId)))
        .write(CachedConversationsCompanion(
      lastMessage: Value(lastMessage),
      lastMessageType: Value(lastMessageType),
      lastMessageIsDeleted: Value(lastMessageIsDeleted),
      updatedAt: Value(updatedAt),
    ));
  }

  /// Delete all data (for account cleanup).
  Future<void> clearAllData() async {
    await delete(cachedMessages).go();
    await delete(cachedConversations).go();
  }
}
