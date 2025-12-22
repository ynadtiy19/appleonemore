class Post {
  final int id;
  final int userId;
  final String? authorName;
  final String? authorAvatar;
  final String title;
  final String contentJson;
  final String plainText;
  final String? firstImage;
  final DateTime createdAt;
  final int likeCount;
  final int commentCount;

  Post({
    required this.id,
    required this.userId,
    this.authorName,
    this.authorAvatar,
    required this.title,
    required this.contentJson,
    required this.plainText,
    this.firstImage,
    required this.createdAt,
    this.likeCount = 0,
    this.commentCount = 0,
  });

  factory Post.fromMap(Map<String, dynamic> map) {
    return Post(
      id: map['id'] is int ? map['id'] : int.parse(map['id'].toString()),
      userId: map['user_id'] is int
          ? map['user_id']
          : int.parse(map['user_id'].toString()),
      // 支持联表查询出来的 nickname 和 avatar_url
      authorName: map['nickname'] ?? 'Unknown',
      authorAvatar: map['avatar_url'],
      title: map['title'] ?? '',
      contentJson: map['content_json'] ?? '',
      plainText: map['plain_text'] ?? '',
      firstImage: map['first_image'],
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
      likeCount: map['like_count'] ?? 0,
      commentCount: map['comment_count'] ?? 0,
    );
  }
}

class Comment {
  final int id;
  final int postId;
  final int userId; // ✅ 新增：关联用户ID
  final String content;
  final String authorName; // 从 Users 表联查
  final String? authorAvatar; // ✅ 新增：从 Users 表联查
  final DateTime createdAt;

  Comment({
    required this.id,
    required this.postId,
    required this.userId,
    required this.content,
    required this.authorName,
    this.authorAvatar,
    required this.createdAt,
  });

  factory Comment.fromMap(Map<String, dynamic> map) {
    return Comment(
      id: map['id'] is int ? map['id'] : int.parse(map['id'].toString()),
      postId: map['post_id'] is int
          ? map['post_id']
          : int.parse(map['post_id'].toString()),
      userId: map['user_id'] is int
          ? map['user_id']
          : int.parse(map['user_id'].toString()),
      content: map['content'] ?? '',
      // 优先使用联表查询的 nickname，如果没有则使用旧字段
      authorName: map['nickname'] ?? map['author_name'] ?? 'Unknown',
      authorAvatar: map['avatar_url'],
      createdAt: DateTime.tryParse(map['created_at'] ?? '') ?? DateTime.now(),
    );
  }
}
