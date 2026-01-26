class Conversation {
  final String id; // The Room ID
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;
  final bool isOnline;
  final String lastMessage;
  final DateTime? updatedAt;
  final int unreadCount;

  Conversation({
    required this.id,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    this.isOnline = false,
    required this.lastMessage,
    this.updatedAt,
    this.unreadCount = 0,
  });

  // Factory: Converts API /conversations/:id response
  factory Conversation.fromHistory(Map<String, dynamic> json) {
    final otherUser = json['otherUser'];
    return Conversation(
      id: json['id'] ?? json['_id'] ?? '',
      otherUserId: otherUser['id'] ?? otherUser['_id'] ?? '',
      otherUserName: otherUser['username'] ?? 'Unknown',
      otherUserAvatar: otherUser['profile_pic'],
      isOnline: otherUser['is_online'] == true,
      lastMessage: json['lastMessage'] ?? 'Start chatting',
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
    );
  }

  // Factory: Converts API /search response
  factory Conversation.fromSearch(Map<String, dynamic> userJson) {
    return Conversation(
      id: '', // Room ID is unknown until we click "Chat"
      otherUserId: userJson['_id'] ?? userJson['id'],
      otherUserName: userJson['username'],
      otherUserAvatar: userJson['profile_pic'],
      isOnline: userJson['is_online'] == true,
      lastMessage: 'Tap to chat', // Default text for search results
    );
  }

  // Helper: Create a copy with updated status (Optimization for immutability)
  Conversation copyWith({bool? isOnline, String? lastMessage, DateTime? time}) {
    return Conversation(
      id: id,
      otherUserId: otherUserId,
      otherUserName: otherUserName,
      otherUserAvatar: otherUserAvatar,
      isOnline: isOnline ?? this.isOnline,
      lastMessage: lastMessage ?? this.lastMessage, // Ensure this updates
      updatedAt: time ?? updatedAt,
      unreadCount: unreadCount,
    );
  }
}
