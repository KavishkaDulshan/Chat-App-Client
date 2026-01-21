class User {
  final String id;
  final String username;
  final String email;
  final String token;
  final String? profilePic;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.token,
    this.profilePic,
  });

  factory User.fromJson(Map<String, dynamic> json, String token) {
    return User(
      id: json['_id'],
      username: json['username'],
      email: json['email'],
      token: token,
      profilePic: json['profile_pic'],
    );
  }
}
