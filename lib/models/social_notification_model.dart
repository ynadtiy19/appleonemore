import 'dart:convert';

class SocialNotificationModel {
  final String id; // UUID 用于去重
  final String type; // "LIKE" 或 "COMMENT"
  final int postId;
  final String postTitle; // 帖子摘要或标题
  final String? postImage; // 帖子缩略图
  final int creatorId; // 接收人ID（帖子作者）
  final String? creatorName; // 接收人ID（帖子作者）
  final int triggerId; // 触发人ID（点赞/评论者）
  final String triggerName; // 触发人昵称
  final String? triggerAvatar; // 触发人头像
  final String? commentContent; // 如果是评论，具体的评论内容
  final int timestamp;

  SocialNotificationModel({
    required this.id,
    required this.type,
    required this.postId,
    required this.postTitle,
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
      // 标记这是一个通知数据，区别于聊天消息
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
