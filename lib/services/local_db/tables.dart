import 'package:drift/drift.dart';

/// Local cache of chat messages for offline reading.
class CachedMessages extends Table {
  // MongoDB _id — primary key
  TextColumn get id => text()();
  TextColumn get conversationId => text()();
  TextColumn get senderId => text()();
  TextColumn get senderName => text().withDefault(const Constant('Unknown'))();
  TextColumn get senderAvatar => text().nullable()();
  TextColumn get content => text()();
  TextColumn get type =>
      text().withDefault(const Constant('text'))(); // text, image, audio
  TextColumn get status =>
      text().withDefault(const Constant('sent'))(); // sent, delivered, read
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get timestamp => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Local cache of conversations for the conversation list.
class CachedConversations extends Table {
  // Room ID — primary key
  TextColumn get id => text()();
  TextColumn get otherUserId => text()();
  TextColumn get otherUserName =>
      text().withDefault(const Constant('Unknown'))();
  TextColumn get otherUserAvatar => text().nullable()();
  TextColumn get lastMessage =>
      text().withDefault(const Constant('Start chatting'))();
  TextColumn get lastMessageType =>
      text().withDefault(const Constant('text'))();
  BoolColumn get lastMessageIsDeleted =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
