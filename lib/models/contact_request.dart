class ContactRequest {
  final String requestId;
  final String fromUserId;
  final String fromUsername;
  final String? fromAvatar;
  final bool fromIsOnline;
  final DateTime? createdAt;

  ContactRequest({
    required this.requestId,
    required this.fromUserId,
    required this.fromUsername,
    this.fromAvatar,
    this.fromIsOnline = false,
    this.createdAt,
  });

  factory ContactRequest.fromJson(Map<String, dynamic> json) {
    return ContactRequest(
      requestId: json['requestId']?.toString() ?? '',
      fromUserId: json['fromUserId']?.toString() ?? '',
      fromUsername: json['fromUsername']?.toString() ?? 'Unknown',
      fromAvatar: json['fromAvatar']?.toString(),
      fromIsOnline: json['fromIsOnline'] == true,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }
}
