import 'dart:convert';

class SocialNotificationModel {
  final String id;
  final String type; // "LIKE", "COMMENT", "FOLLOW" 🔥 新增 FOLLOW
  final int postId; // 对于 FOLLOW，设为 0 或 -1
  final String postTitle; // 对于 FOLLOW，设为空字符串
  final String? postImage;
  final int creatorId; // 被关注人ID (接收者)
  final String? creatorName;
  final int triggerId; // 发起关注的人ID
  final String triggerName; // 发起人昵称
  final String? triggerAvatar; // 发起人头像
  final String? commentContent;
  final int timestamp;

  SocialNotificationModel({
    required this.id,
    required this.type,
    this.postId = 0, // 🔥 默认为 0
    this.postTitle = '', // 🔥 默认为空
    this.postImage,
    required this.creatorId,
    required this.triggerId,
    required this.triggerName,
    this.creatorName,
    this.triggerAvatar,
    this.commentContent,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'type': type,
      'postId': postId,
      'postTitle': postTitle,
      'postImage': postImage,
      'creatorId': creatorId,
      'triggerId': triggerId,
      'triggerName': triggerName,
      'triggerAvatar': triggerAvatar,
      'commentContent': commentContent,
      'timestamp': timestamp,
      'dataType': 'SOCIAL_NOTIFICATION',
    };
  }

  factory SocialNotificationModel.fromMap(Map<String, dynamic> map) {
    return SocialNotificationModel(
      id: map['id'] ?? '',
      type: map['type'] ?? 'LIKE',
      postId: map['postId']?.toInt() ?? 0,
      postTitle: map['postTitle'] ?? '',
      postImage: map['postImage'],
      creatorId: map['creatorId']?.toInt() ?? 0,
      triggerId: map['triggerId']?.toInt() ?? 0,
      triggerName: map['triggerName'] ?? '',
      creatorName: map['creatorName'] ?? '',
      triggerAvatar: map['triggerAvatar'],
      commentContent: map['commentContent'],
      timestamp: map['timestamp']?.toInt() ?? 0,
    );
  }

  String toJson() => json.encode(toMap());

  factory SocialNotificationModel.fromJson(String source) =>
      SocialNotificationModel.fromMap(json.decode(source));
}
