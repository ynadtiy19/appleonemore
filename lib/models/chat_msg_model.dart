import 'dart:convert';

class ChatMsgModel {
  final String id;
  final String conversationId; // 单聊是 "1_2"，群聊是 "GROUP_GLOBAL"
  final int senderId;
  final String senderName;
  final String senderAvatar;
  final int receiverId; // 群聊时可为 0
  final String receiverAtsign;
  final String content;
  final int timestamp;
  final int type; // 1:文本, 2:图片, 99:心跳

  ChatMsgModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.receiverId,
    required this.receiverAtsign,
    required this.content,
    required this.timestamp,
    this.type = 1,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cid': conversationId,
      'sid': senderId,
      'sName': senderName,
      'sAvatar': senderAvatar,
      'rid': receiverId,
      'rAtsign': receiverAtsign,
      'msg': content,
      'ts': timestamp,
      'type': type,
    };
  }

  factory ChatMsgModel.fromMap(Map<String, dynamic> map) {
    return ChatMsgModel(
      id: map['id']?.toString() ?? '',
      conversationId: map['cid']?.toString() ?? '',
      senderId: map['sid'] is int
          ? map['sid']
          : int.tryParse(map['sid'].toString()) ?? 0,
      senderName: map['sName'] ?? 'Unknown',
      senderAvatar: map['sAvatar'] ?? '',
      receiverId: map['rid'] is int
          ? map['rid']
          : int.tryParse(map['rid'].toString()) ?? 0,
      receiverAtsign: map['rAtsign'] ?? '',
      content: map['msg'] ?? '',
      timestamp: map['ts'] is int
          ? map['ts']
          : int.tryParse(map['ts'].toString()) ?? 0,
      type: map['type'] is int
          ? map['type']
          : int.tryParse(map['type'].toString()) ?? 1,
    );
  }

  String toJson() => jsonEncode(toMap());
}
