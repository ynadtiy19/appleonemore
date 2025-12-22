class User {
  final int id;
  final String username;
  final String? nickname;
  final String? avatarUrl;
  final String? bio;
  final String? externalLink;
  final int followingCount;
  final int followersCount;
  final bool isOnline;
  final String token;

  User({
    required this.id,
    required this.username,
    this.nickname,
    this.avatarUrl,
    this.bio,
    this.externalLink,
    this.followingCount = 0,
    this.followersCount = 0,
    this.isOnline = false,
    required this.token,
  });

  factory User.fromMap(Map<String, dynamic> map) {
    return User(
      id: map['id'] is int ? map['id'] : int.parse(map['id'].toString()),
      username: map['username'] ?? '',
      nickname: map['nickname'],
      avatarUrl: map['avatar_url'],
      bio: map['bio'],
      externalLink: map['external_link'],
      followingCount: map['following_count'] ?? 0,
      followersCount: map['followers_count'] ?? 0,
      isOnline: (map['is_online'] == 1),
      token: map['token'] ?? '',
    );
  }
}
