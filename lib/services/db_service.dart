import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:libsql_dart/libsql_dart.dart';

import '../models/chat_msg_model.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import '../utils/constants.dart';

class DbService extends GetxService {
  LibsqlClient? _client;
  LibsqlClient? _msgClient;

  static const String _tblMessages = "messages_v3";
  static const String _tblConversations = "conversations_v3";
  // 🔥 新增：群聊消息表
  static const String _tblGroupMessages = "group_messages_v1";

  static const String _tblPosts = "posts_v3";
  static const String _tblComments = "comments_v3";
  static const String _tblLikes = "likes_v3";

  Future<DbService> init() async {
    if (_client == null) {
      _client = LibsqlClient.remote(
        Constants.dbUrl,
        authToken: Constants.dbToken,
      );
      await _client!.connect();
      await _createMainTables();
    }
    if (_msgClient == null) {
      _msgClient = LibsqlClient.remote(
        Constants.msgDbUrl,
        authToken: Constants.msgDbToken,
      );
      await _msgClient!.connect();
      await _createChatTables();
    }
    return this;
  }

  String getConversationId(int uid1, int uid2) {
    return uid1 < uid2 ? "${uid1}_$uid2" : "${uid2}_$uid1";
  }

  // ==========================================
  // 1. 群聊消息存储 (Group Chat) - 新增
  // ==========================================

  // 获取群聊历史
  Future<List<ChatMsgModel>> getGroupMessages({
    int limit = 50,
    int offset = 0,
  }) async {
    final rs = await _msgClient!.query(
      "SELECT * FROM $_tblGroupMessages ORDER BY created_at DESC LIMIT ? OFFSET ?",
      positional: [limit, offset],
    );

    return rs.map((row) {
      return ChatMsgModel(
        id: row['id'] as String,
        conversationId: "GROUP_GLOBAL", // 固定 ID
        senderId: row['sender_id'] as int,
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

  // 存储群聊消息
  Future<void> saveGroupMessage(ChatMsgModel msg) async {
    final nowStr = DateTime.fromMillisecondsSinceEpoch(
      msg.timestamp,
    ).toIso8601String();

    try {
      await _msgClient!.execute(
        "INSERT INTO $_tblGroupMessages (id, sender_id, content, message_type, created_at, sender_name, sender_avatar) VALUES (?, ?, ?, ?, ?, ?, ?)",
        positional: [
          msg.id,
          msg.senderId,
          msg.content,
          msg.type,
          nowStr,
          msg.senderName,
          msg.senderAvatar,
        ],
      );
    } catch (e) {
      debugPrint("❌ [DB] Save Group Message Error: $e");
    }
  }

  // ==========================================
  // 2. 单聊消息存储 (Private Chat) - 保持不变
  // ==========================================

  Future<void> saveMessage(ChatMsgModel msg, {required bool isIncoming}) async {
    final nowStr = DateTime.fromMillisecondsSinceEpoch(
      msg.timestamp,
    ).toIso8601String();

    try {
      await _msgClient!.execute(
        "INSERT INTO $_tblMessages (id, sender_id, receiver_id, conversation_id, content, message_type, is_read, created_at, sender_name, sender_avatar) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        positional: [
          msg.id,
          msg.senderId,
          msg.receiverId,
          msg.conversationId,
          msg.content,
          msg.type,
          isIncoming ? 0 : 1,
          nowStr,
          msg.senderName,
          msg.senderAvatar,
        ],
      );

      String unreadSql = isIncoming
          ? "unread_count = unread_count + 1"
          : "unread_count = 0";
      int peerId = isIncoming ? msg.senderId : msg.receiverId;
      String peerName = isIncoming ? msg.senderName : "User_$peerId";
      String peerAvatar = isIncoming ? msg.senderAvatar : "";

      await _msgClient!.execute(
        """
        INSERT INTO $_tblConversations (conversation_id, peer_id, peer_name, peer_avatar, last_message, last_updated_at, unread_count)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(conversation_id) DO UPDATE SET
          peer_name = CASE WHEN ? != '' THEN ? ELSE peer_name END,
          peer_avatar = CASE WHEN ? != '' THEN ? ELSE peer_avatar END,
          last_message = excluded.last_message,
          last_updated_at = excluded.last_updated_at,
          $unreadSql
        """,
        positional: [
          msg.conversationId,
          peerId,
          peerName,
          peerAvatar,
          msg.content,
          nowStr,
          isIncoming ? 1 : 0,
          peerName,
          peerName,
          peerAvatar,
          peerAvatar,
        ],
      );
    } catch (e) {
      debugPrint("❌ [DB] Save Message Error: $e");
    }
  }

  Future<List<Map<String, dynamic>>> getConversations() async {
    return await _msgClient!.query(
      "SELECT * FROM $_tblConversations ORDER BY last_updated_at DESC",
    );
  }

  Future<List<ChatMsgModel>> getChatHistory(
    String convId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final rs = await _msgClient!.query(
      "SELECT * FROM $_tblMessages WHERE conversation_id = ? ORDER BY created_at DESC LIMIT ? OFFSET ?",
      positional: [convId, limit, offset],
    );

    return rs.map((row) {
      return ChatMsgModel(
        id: row['id'] as String,
        conversationId: row['conversation_id'] as String,
        senderId: row['sender_id'] as int,
        senderName: row['sender_name'] ?? '',
        senderAvatar: row['sender_avatar'] ?? '',
        receiverId: row['receiver_id'] as int,
        receiverAtsign: '',
        content: row['content'] as String,
        timestamp: DateTime.parse(row['created_at']).millisecondsSinceEpoch,
        type: row['message_type'] is int
            ? row['message_type']
            : int.tryParse(row['message_type'].toString()) ?? 1,
      );
    }).toList();
  }

  Future<void> clearUnreadCount(String convId) async {
    try {
      await _msgClient!.execute(
        "UPDATE $_tblConversations SET unread_count = 0 WHERE conversation_id = ?",
        positional: [convId],
      );
    } catch (e) {
      debugPrint("❌ [DB] Clear Unread Error: $e");
    }
  }

  Future<void> markMessageRead(String msgId) async {
    try {
      await _msgClient!.execute(
        "UPDATE $_tblMessages SET is_read = 1 WHERE id = ?",
        positional: [msgId],
      );
    } catch (e) {
      debugPrint("❌ [DB] Mark Read Error: $e");
    }
  }

  Future<void> clearChatHistory(String convId) async {
    await _msgClient!.execute(
      "DELETE FROM $_tblMessages WHERE conversation_id = ?",
      positional: [convId],
    );
    await _msgClient!.execute(
      "DELETE FROM $_tblConversations WHERE conversation_id = ?",
      positional: [convId],
    );
  }

  // ==========================================
  // 其他表操作 (Posts, Users...) - 保持不变
  // ==========================================

  // ... (省略 Posts/Comments/Likes 相关代码，保持原样) ...
  Future<Post?> getPost(int id) async {
    final sql =
        """
      SELECT p.*, u.nickname, u.avatar_url,
        (SELECT COUNT(*) FROM $_tblLikes WHERE post_id = p.id) as like_count,
        (SELECT COUNT(*) FROM $_tblComments WHERE post_id = p.id) as comment_count
      FROM $_tblPosts p 
      LEFT JOIN users u ON p.user_id = u.id
      WHERE p.id = ?
    """;
    final result = await _client!.query(sql, positional: [id]);
    if (result.isEmpty) return null;
    return Post.fromMap(result.first);
  }

  Future<List<Post>> getPosts() async {
    final sql =
        """
      SELECT p.*, u.nickname, u.avatar_url,
        (SELECT COUNT(*) FROM $_tblLikes WHERE post_id = p.id) as like_count,
        (SELECT COUNT(*) FROM $_tblComments WHERE post_id = p.id) as comment_count
      FROM $_tblPosts p
      LEFT JOIN users u ON p.user_id = u.id
      ORDER BY p.id DESC
    """;
    final result = await _client!.query(sql);
    return result.map((row) => Post.fromMap(row)).toList();
  }

  Future<List<Post>> getUserPosts(int userId) async {
    final sql =
        """
      SELECT p.*, u.nickname, u.avatar_url,
        (SELECT COUNT(*) FROM $_tblLikes WHERE post_id = p.id) as like_count,
        (SELECT COUNT(*) FROM $_tblComments WHERE post_id = p.id) as comment_count
      FROM $_tblPosts p
      LEFT JOIN users u ON p.user_id = u.id
      WHERE p.user_id = ?
      ORDER BY p.id DESC
    """;
    final result = await _client!.query(sql, positional: [userId]);
    return result.map((row) => Post.fromMap(row)).toList();
  }

  Future<void> createPost(
    int userId,
    String title,
    String json,
    String plain,
    String? firstImage,
  ) async {
    await _client!.execute(
      "INSERT INTO $_tblPosts (user_id, title, content_json, plain_text, first_image, created_at) VALUES (?, ?, ?, ?, ?, ?)",
      positional: [
        userId,
        title,
        json,
        plain,
        firstImage,
        DateTime.now().toIso8601String(),
      ],
    );
  }

  Future<void> deletePost(int postId) async {
    await _client!.execute(
      "DELETE FROM $_tblComments WHERE post_id = ?",
      positional: [postId],
    );
    await _client!.execute(
      "DELETE FROM $_tblLikes WHERE post_id = ?",
      positional: [postId],
    );
    await _client!.execute(
      "DELETE FROM $_tblPosts WHERE id = ?",
      positional: [postId],
    );
  }

  Future<List<Comment>> getComments(int postId) async {
    final sql =
        """
      SELECT c.*, u.nickname, u.avatar_url, u.username
      FROM $_tblComments c
      LEFT JOIN users u ON c.user_id = u.id
      WHERE c.post_id = ?
      ORDER BY c.created_at ASC
    """;
    final result = await _client!.query(sql, positional: [postId]);
    return result.map((row) => Comment.fromMap(row)).toList();
  }

  Future<void> addComment(int postId, int userId, String content) async {
    await _client!.execute(
      "INSERT INTO $_tblComments (post_id, user_id, content, created_at) VALUES (?, ?, ?, ?)",
      positional: [postId, userId, content, DateTime.now().toIso8601String()],
    );
  }

  Future<bool> hasUserLiked(int postId, int userId) async {
    final result = await _client!.query(
      "SELECT id FROM $_tblLikes WHERE post_id = ? AND user_id = ?",
      positional: [postId, userId],
    );
    return result.isNotEmpty;
  }

  Future<bool> toggleLike(int postId, int userId) async {
    final check = await _client!.query(
      "SELECT id FROM $_tblLikes WHERE post_id = ? AND user_id = ?",
      positional: [postId, userId],
    );
    if (check.isNotEmpty) {
      await _client!.execute(
        "DELETE FROM $_tblLikes WHERE id = ?",
        positional: [check.first['id']],
      );
      return false;
    } else {
      await _client!.execute(
        "INSERT INTO $_tblLikes (post_id, user_id, created_at) VALUES (?, ?, ?)",
        positional: [postId, userId, DateTime.now().toIso8601String()],
      );
      return true;
    }
  }

  Future<bool> checkFollowStatus(int followerId, int followingId) async {
    try {
      final rs = await _client!.query(
        "SELECT * FROM follows WHERE follower_id = ? AND following_id = ?",
        positional: [followerId, followingId],
      );
      return rs.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  Future<bool> toggleFollow(int followerId, int followingId) async {
    final isFollowing = await checkFollowStatus(followerId, followingId);
    if (isFollowing) {
      await _client!.execute(
        "DELETE FROM follows WHERE follower_id = ? AND following_id = ?",
        positional: [followerId, followingId],
      );
      await _client!.execute(
        "UPDATE users SET following_count = following_count - 1 WHERE id = ?",
        positional: [followerId],
      );
      await _client!.execute(
        "UPDATE users SET followers_count = followers_count - 1 WHERE id = ?",
        positional: [followingId],
      );
      return false;
    } else {
      await _client!.execute(
        "INSERT INTO follows (follower_id, following_id) VALUES (?, ?)",
        positional: [followerId, followingId],
      );
      await _client!.execute(
        "UPDATE users SET following_count = following_count + 1 WHERE id = ?",
        positional: [followerId],
      );
      await _client!.execute(
        "UPDATE users SET followers_count = followers_count + 1 WHERE id = ?",
        positional: [followingId],
      );
      return true;
    }
  }

  Future<User?> login(String username, String password) async {
    final rs = await _client!.query(
      "SELECT * FROM users WHERE username = ? AND password = ?",
      positional: [username, password],
    );
    return rs.isNotEmpty ? User.fromMap(rs.first) : null;
  }

  Future<User?> register(String username, String password, String token) async {
    try {
      await _client!.execute(
        "INSERT INTO users (username, password, token, nickname) VALUES (?, ?, ?, ?)",
        positional: [username, password, token, "User_$username"],
      );
      return login(username, password);
    } catch (e) {
      return null;
    }
  }

  Future<User?> getUserByToken(String token) async {
    final rs = await _client!.query(
      "SELECT * FROM users WHERE token = ?",
      positional: [token],
    );
    return rs.isNotEmpty ? User.fromMap(rs.first) : null;
  }

  Future<User?> getUserById(int id) async {
    final rs = await _client!.query(
      "SELECT * FROM users WHERE id = ?",
      positional: [id],
    );
    return rs.isNotEmpty ? User.fromMap(rs.first) : null;
  }

  Future<List<User>> getAllUsersExcept(int myId) async {
    final rs = await _client!.query(
      "SELECT * FROM users WHERE id != ?",
      positional: [myId],
    );
    return rs.map((e) => User.fromMap(e)).toList();
  }

  Future<void> updateOnlineStatus(int uid, bool isOnline) async {
    await _client!.execute(
      "UPDATE users SET is_online = ? WHERE id = ?",
      positional: [isOnline ? 1 : 0, uid],
    );
  }

  Future<void> updateUserInfo(
    int id,
    String nickname,
    String bio,
    String link,
    String avatarUrl,
  ) async {
    await _client!.execute(
      "UPDATE users SET nickname = ?, bio = ?, external_link = ?, avatar_url = ? WHERE id = ?",
      positional: [nickname, bio, link, avatarUrl, id],
    );
  }

  Future<void> _createMainTables() async {
    await _client!.execute("""
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        username TEXT UNIQUE,
        password TEXT,
        nickname TEXT,
        avatar_url TEXT,
        bio TEXT,
        token TEXT,
        is_online INTEGER DEFAULT 0
      )
    """);

    await _client!.execute("""
      CREATE TABLE IF NOT EXISTS $_tblPosts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER,
        title TEXT,
        content_json TEXT,
        plain_text TEXT,
        first_image TEXT,
        created_at TEXT
      )
    """);

    await _client!.execute("""
      CREATE TABLE IF NOT EXISTS $_tblComments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        post_id INTEGER,
        user_id INTEGER, 
        content TEXT,
        created_at TEXT
      )
    """);

    await _client!.execute("""
      CREATE TABLE IF NOT EXISTS $_tblLikes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        post_id INTEGER,
        user_id INTEGER,
        created_at TEXT
      )
    """);

    await _client!.execute("""
      CREATE TABLE IF NOT EXISTS follows (
        follower_id INTEGER,
        following_id INTEGER,
        created_at TEXT,
        PRIMARY KEY(follower_id, following_id)
      )
    """);
  }

  Future<void> _createChatTables() async {
    await _msgClient!.execute("""
      CREATE TABLE IF NOT EXISTS $_tblMessages (
        id TEXT PRIMARY KEY,
        sender_id INTEGER NOT NULL,
        receiver_id INTEGER NOT NULL,
        conversation_id TEXT NOT NULL,
        content TEXT,
        message_type INTEGER DEFAULT 1,
        is_read INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        sender_name TEXT, 
        sender_avatar TEXT
      )
    """);

    // 🔥 新增群聊表
    await _msgClient!.execute("""
      CREATE TABLE IF NOT EXISTS $_tblGroupMessages (
        id TEXT PRIMARY KEY,
        sender_id INTEGER NOT NULL,
        content TEXT,
        message_type INTEGER DEFAULT 1,
        created_at TEXT NOT NULL,
        sender_name TEXT, 
        sender_avatar TEXT
      )
    """);

    await _msgClient!.execute("""
      CREATE TABLE IF NOT EXISTS $_tblConversations (
        conversation_id TEXT PRIMARY KEY,
        peer_id INTEGER,
        peer_name TEXT,
        peer_avatar TEXT,
        last_message TEXT,
        last_updated_at TEXT,
        unread_count INTEGER DEFAULT 0
      )
    """);
  }
}
