class ContactRequest {
  final String id;
  // For incoming requests
  final String? fromUserId;
  final String? fromUsername;
  final String? fromAvatar;
  final bool? fromIsOnline;
  
  // For outgoing requests
  final String? toUserId;
  final String? toUsername;
  final String? toAvatar;
  final bool? toIsOnline;

  final DateTime createdAt;
  final bool isIncoming;

  ContactRequest({
    required this.id,
    this.fromUserId,
    this.fromUsername,
    this.fromAvatar,
    this.fromIsOnline,
    this.toUserId,
    this.toUsername,
    this.toAvatar,
    this.toIsOnline,
    required this.createdAt,
    required this.isIncoming,
  });

  factory ContactRequest.fromJson(Map<String, dynamic> json, {bool isIncoming = true}) {
    return ContactRequest(
      id: json['requestId'] ?? json['_id'] ?? '',
      fromUserId: json['fromUserId'],
      fromUsername: json['fromUsername'],
      fromAvatar: json['fromAvatar'],
      fromIsOnline: json['fromIsOnline'] == true,
      toUserId: json['toUserId'],
      toUsername: json['toUsername'],
      toAvatar: json['toAvatar'],
      toIsOnline: json['toIsOnline'] == true,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
      isIncoming: isIncoming,
    );
  }
}
