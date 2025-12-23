import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../models/chat_msg_model.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';

class DbService extends GetxService {
  // 🔥 API 路由地址
  static const String _apiEndpoint =
      "https://mydiumtify.globeapp.dev/youtubevideo";

  Future<DbService> init() async {
    debugPrint("🚀 [DbService] Initialized in API Mode.");
    return this;
  }

  /// 内部通用请求方法
  Future<dynamic> _post(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    try {
      if (kDebugMode) {
        // print("📡 [API] Request: $action");
      }

      final response = await http.post(
        Uri.parse(_apiEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': action, 'payload': payload}),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        if (body['status'] == 'ok') {
          return body['data'];
        } else {
          debugPrint("⚠️ [API Error] Action: $action, Msg: ${body['error']}");
          return null;
        }
      } else {
        debugPrint("❌ [Http Error] ${response.statusCode}: ${response.body}");
        return null;
      }
    } catch (e) {
      debugPrint("❌ [Exception] $e");
      return null;
    }
  }

  String getConversationId(int uid1, int uid2) {
    return uid1 < uid2 ? "${uid1}_$uid2" : "${uid2}_$uid1";
  }

  // ==========================================
  // 1. 群聊消息存储 (Group Chat)
  // ==========================================

  // 获取群聊历史
  Future<List<ChatMsgModel>> getGroupMessages({
    int limit = 50,
    int offset = 0,
  }) async {
    final result = await _post('GET_GROUP_MESSAGES', {
      'limit': limit,
      'offset': offset,
    });

    if (result is List) {
      return result.map((row) {
        return ChatMsgModel(
          id: row['id'] as String,
          conversationId: "GROUP_GLOBAL", // 固定 ID
          senderId: row['sender_id'] is int
              ? row['sender_id']
              : int.parse(row['sender_id'].toString()),
          senderName: row['sender_name'] ?? '',
          senderAvatar: row['sender_avatar'] ?? '',
          receiverId: 0,
          receiverAtsign: '',
          content: row['content'] as String,
          timestamp: DateTime.parse(row['created_at']).millisecondsSinceEpoch,
          type: row['message_type'] is int
              ? row['message_type']
              : int.tryParse(row['message_type'].toString()) ?? 1,
        );
      }).toList();
    }
    return [];
  }

  // 存储群聊消息
  Future<void> saveGroupMessage(ChatMsgModel msg) async {
    final nowStr = DateTime.fromMillisecondsSinceEpoch(
      msg.timestamp,
    ).toIso8601String();

    await _post('SAVE_GROUP_MESSAGE', {
      'id': msg.id,
      'sender_id': msg.senderId,
      'content': msg.content,
      'message_type': msg.type,
      'created_at': nowStr,
      'sender_name': msg.senderName,
      'sender_avatar': msg.senderAvatar,
    });
  }

  // ==========================================
  // 2. 单聊消息存储 (Private Chat)
  // ==========================================

  Future<void> saveMessage(ChatMsgModel msg, {required bool isIncoming}) async {
    final nowStr = DateTime.fromMillisecondsSinceEpoch(
      msg.timestamp,
    ).toIso8601String();

    int peerId = isIncoming ? msg.senderId : msg.receiverId;
    String peerName = isIncoming ? msg.senderName : "User_$peerId";
    String peerAvatar = isIncoming ? msg.senderAvatar : "";

    await _post('SAVE_MESSAGE', {
      'isIncoming': isIncoming,
      'id': msg.id,
      'sender_id': msg.senderId,
      'receiver_id': msg.receiverId,
      'conversation_id': msg.conversationId,
      'content': msg.content,
      'message_type': msg.type,
      'created_at': nowStr,
      'sender_name': msg.senderName,
      'sender_avatar': msg.senderAvatar,
      // Conversation params
      'peer_id': peerId,
      'peer_name': peerName,
      'peer_avatar': peerAvatar,
    });
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    final result = await _post('GET_CONVERSATIONS');
    if (result is List) {
      return result.cast<Map<String, dynamic>>();
    }
    return [];
  }

  Future<List<ChatMsgModel>> getChatHistory(
    String convId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final result = await _post('GET_CHAT_HISTORY', {
      'conversation_id': convId,
      'limit': limit,
      'offset': offset,
    });

    if (result is List) {
      return result.map((row) {
        return ChatMsgModel(
          id: row['id'] as String,
          conversationId: row['conversation_id'] as String,
          senderId: row['sender_id'] is int
              ? row['sender_id']
              : int.parse(row['sender_id'].toString()),
          senderName: row['sender_name'] ?? '',
          senderAvatar: row['sender_avatar'] ?? '',
          receiverId: row['receiver_id'] is int
              ? row['receiver_id']
              : int.parse(row['receiver_id'].toString()),
          receiverAtsign: '',
          content: row['content'] as String,
          timestamp: DateTime.parse(row['created_at']).millisecondsSinceEpoch,
          type: row['message_type'] is int
              ? row['message_type']
              : int.tryParse(row['message_type'].toString()) ?? 1,
        );
      }).toList();
    }
    return [];
  }

  Future<void> clearUnreadCount(String convId) async {
    await _post('CLEAR_UNREAD_COUNT', {'conversation_id': convId});
  }

  Future<void> markMessageRead(String msgId) async {
    await _post('MARK_MESSAGE_READ', {'msg_id': msgId});
  }

  Future<void> clearChatHistory(String convId) async {
    await _post('CLEAR_CHAT_HISTORY', {'conversation_id': convId});
  }

  // ==========================================
  // 其他表操作 (Posts, Users...)
  // ==========================================

  Future<Post?> getPost(int id) async {
    final result = await _post('GET_POST', {'id': id});
    if (result != null) {
      return Post.fromMap(result);
    }
    return null;
  }

  Future<List<Post>> getPosts() async {
    final result = await _post('GET_POSTS');
    if (result is List) {
      return result.map((row) => Post.fromMap(row)).toList();
    }
    return [];
  }

  Future<List<Post>> getUserPosts(int userId) async {
    final result = await _post('GET_USER_POSTS', {'user_id': userId});
    if (result is List) {
      return result.map((row) => Post.fromMap(row)).toList();
    }
    return [];
  }

  Future<void> createPost(
    int userId,
    String title,
    String json,
    String plain,
    String? firstImage,
  ) async {
    await _post('CREATE_POST', {
      'user_id': userId,
      'title': title,
      'content_json': json,
      'plain_text': plain,
      'first_image': firstImage,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deletePost(int postId) async {
    await _post('DELETE_POST', {'post_id': postId});
  }

  Future<List<Comment>> getComments(int postId) async {
    final result = await _post('GET_COMMENTS', {'post_id': postId});
    if (result is List) {
      return result.map((row) => Comment.fromMap(row)).toList();
    }
    return [];
  }

  Future<void> addComment(int postId, int userId, String content) async {
    await _post('ADD_COMMENT', {
      'post_id': postId,
      'user_id': userId,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<bool> hasUserLiked(int postId, int userId) async {
    final result = await _post('HAS_USER_LIKED', {
      'post_id': postId,
      'user_id': userId,
    });
    return result == true;
  }

  Future<bool> toggleLike(int postId, int userId) async {
    final result = await _post('TOGGLE_LIKE', {
      'post_id': postId,
      'user_id': userId,
      'created_at': DateTime.now().toIso8601String(),
    });
    return result == true;
  }

  Future<bool> checkFollowStatus(int followerId, int followingId) async {
    final result = await _post('CHECK_FOLLOW_STATUS', {
      'follower_id': followerId,
      'following_id': followingId,
    });
    return result == true;
  }

  Future<bool> toggleFollow(int followerId, int followingId) async {
    final result = await _post('TOGGLE_FOLLOW', {
      'follower_id': followerId,
      'following_id': followingId,
    });
    return result == true;
  }

  Future<User?> login(String username, String password) async {
    final result = await _post('LOGIN', {
      'username': username,
      'password': password,
    });
    if (result != null) {
      return User.fromMap(result);
    }
    return null;
  }

  Future<User?> register(String username, String password, String token) async {
    final result = await _post('REGISTER', {
      'username': username,
      'password': password,
      'token': token,
    });
    if (result != null) {
      return User.fromMap(result);
    }
    return null;
  }

  Future<User?> getUserByToken(String token) async {
    final result = await _post('GET_USER_BY_TOKEN', {'token': token});
    if (result != null) {
      return User.fromMap(result);
    }
    return null;
  }

  Future<User?> getUserById(int id) async {
    final result = await _post('GET_USER_BY_ID', {'id': id});
    if (result != null) {
      return User.fromMap(result);
    }
    return null;
  }

  Future<List<User>> getAllUsersExcept(int myId) async {
    final result = await _post('GET_ALL_USERS_EXCEPT', {'my_id': myId});
    if (result is List) {
      return result.map((e) => User.fromMap(e)).toList();
    }
    return [];
  }

  Future<void> updateOnlineStatus(int uid, bool isOnline) async {
    await _post('UPDATE_ONLINE_STATUS', {'id': uid, 'is_online': isOnline});
  }

  Future<void> updateUserInfo(
    int id,
    String nickname,
    String bio,
    String link,
    String avatarUrl,
  ) async {
    await _post('UPDATE_USER_INFO', {
      'id': id,
      'nickname': nickname,
      'bio': bio,
      'link': link,
      'avatar_url': avatarUrl,
    });
  }
}
