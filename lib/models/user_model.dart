class User {
  final String id;
  final String username;
  final String email;
  final String token;
  final String? profilePic;
  final String? e2ePublicKey;
  final int e2eKeyVersion;
  final bool showNotificationPreview;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.token,
    this.profilePic,
    this.e2ePublicKey,
    this.e2eKeyVersion = 1,
    this.showNotificationPreview = false,
  });

  factory User.fromJson(Map<String, dynamic> json, String token) {
    return User(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      username: json['username'] ?? 'Unknown',
      email: json['email'],
      token: token,
      profilePic: json['profile_pic'],
      e2ePublicKey: json['e2e_public_key'],
      e2eKeyVersion: json['e2e_key_version'] ?? 1,
      showNotificationPreview: json['settings']?['showNotificationPreview'] ?? false,
    );
  }
}
