class User {
  final String id;
  final String username;
  final String email;
  final String token;
  final String? profilePic;
  final String? e2ePublicKey;
  final int e2eKeyVersion;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.token,
    this.profilePic,
    this.e2ePublicKey,
    this.e2eKeyVersion = 1,
  });

  factory User.fromJson(Map<String, dynamic> json, String token) {
    return User(
      id: json['_id'],
      username: json['username'],
      email: json['email'],
      token: token,
      profilePic: json['profile_pic'],
      e2ePublicKey: json['e2e_public_key'],
      e2eKeyVersion: json['e2e_key_version'] ?? 1,
    );
  }
}
