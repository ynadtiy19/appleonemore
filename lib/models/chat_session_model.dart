import 'user_model.dart';

class ChatSession {
  final String conversationId;
  final int otherUserId;
  final String lastMessage;
  final DateTime lastUpdatedAt;
  final int unreadCount;
  final int lastSenderId;

  // 关联的用户信息
  User? otherUser;

  ChatSession({
    required this.conversationId,
    required this.otherUserId,
    required this.lastMessage,
    required this.lastUpdatedAt,
    required this.unreadCount,
    required this.lastSenderId,
    this.otherUser,
  });

  factory ChatSession.fromMap(Map<String, dynamic> map, int myId) {
    // 判断谁是对方
    int u = map['user_u'];
    int v = map['user_v'];
    int otherId = (u == myId) ? v : u;
    int myUnread = (u == myId) ? map['unread_count_u'] : map['unread_count_v'];

    return ChatSession(
      conversationId: map['conversation_id'],
      otherUserId: otherId,
      lastMessage: map['last_message'] ?? "",
      lastUpdatedAt: DateTime.parse(map['last_updated_at']),
      unreadCount: myUnread,
      lastSenderId: map['last_sender_id'],
    );
  }
}
