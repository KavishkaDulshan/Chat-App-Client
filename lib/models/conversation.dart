class Conversation {
  final String id;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  final bool isOnline;
  final String lastMessage;
  final bool lastMessageIsDeleted;
  final bool lastMessageIsEncrypted;
  final DateTime? updatedAt;
  final int unreadCount;
  /// 'none' | 'pending_sent' | 'pending_received' | 'contacts'
  /// Only populated for search results; real conversations default to 'contacts'.
  final String contactStatus;
  /// Only populated for pending_received — the request ID needed to accept/decline
  final String? pendingRequestId;

  Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    this.isOnline = false,
    required this.lastMessage,
    this.lastMessageIsDeleted = false,
    this.lastMessageIsEncrypted = false,
    this.updatedAt,
    this.unreadCount = 0,
    this.contactStatus = 'contacts',
    this.pendingRequestId,
  });

  // Factory: Converts API /conversations/:id response
  factory Conversation.fromHistory(Map<String, dynamic> json) {
    final otherUser = json['otherUser'];
    final rawLastMessage = json['lastMessage'] ?? 'Start chatting';
    // Detect if the backend returned a raw E2E ciphertext (not yet decrypted)
    final isEncrypted = rawLastMessage is String &&
        rawLastMessage.startsWith('e2e:v1:');
    return Conversation(
      id: json['id'] ?? json['_id'] ?? '',
      otherUserId: otherUser['id'] ?? otherUser['_id'] ?? '',
      otherUserName: otherUser['username'] ?? 'Unknown',
      otherUserAvatar: otherUser['profile_pic'],
      isOnline: otherUser['is_online'] == true,
      lastMessage: rawLastMessage,
      lastMessageIsDeleted: json['lastMessageIsDeleted'] ?? false,
      lastMessageIsEncrypted: isEncrypted,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
      unreadCount: json['unreadCount'] ?? 0,
    );
  }

  // Factory: Converts API /search response
  factory Conversation.fromSearch(Map<String, dynamic> userJson) {
    return Conversation(
      id: '',
      otherUserId: userJson['_id'] ?? userJson['id'],
      otherUserName: userJson['username'],
      otherUserAvatar: userJson['profile_pic'],
      isOnline: userJson['is_online'] == true,
      lastMessage: 'Tap to chat',
      contactStatus: userJson['contactStatus']?.toString() ?? 'none',
      pendingRequestId: userJson['pendingRequestId']?.toString(),
    );
  }

  Conversation copyWith({
    bool? isOnline,
    String? lastMessage,
    bool? lastMessageIsDeleted,
    bool? lastMessageIsEncrypted,
    DateTime? time,
    int? unreadCount,
    String? contactStatus,
    String? pendingRequestId,
  }) {
    return Conversation(
      id: id,
      otherUserId: otherUserId,
      otherUserName: otherUserName,
      otherUserAvatar: otherUserAvatar,
      isOnline: isOnline ?? this.isOnline,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageIsDeleted: lastMessageIsDeleted ?? this.lastMessageIsDeleted,
      lastMessageIsEncrypted:
          lastMessageIsEncrypted ?? this.lastMessageIsEncrypted,
      updatedAt: time ?? updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      contactStatus: contactStatus ?? this.contactStatus,
      pendingRequestId: pendingRequestId ?? this.pendingRequestId,
    );
  }
}
