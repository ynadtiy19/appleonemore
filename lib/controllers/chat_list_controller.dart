import 'package:get/get.dart';

import '../models/chat_session_model.dart';
import '../models/user_model.dart';
import '../services/db_service.dart';
import '../services/storage_service.dart';

class ChatListController extends GetxController {
  final DbService db = Get.find();
  final StorageService storage = Get.find();

  var sessions = <ChatSession>[].obs;
  var allUsers = <User>[].obs;

  var isLoading = true.obs;
  bool _hasLoadedOnce = false;

  @override
  void onInit() {
    super.onInit();
    loadSessions();
    fetchAllUsers();
  }

  Future<void> loadSessions() async {
    try {
      if (!_hasLoadedOnce) isLoading(true);

      int? myId = storage.getUserId();
      if (myId == null) return;

      // ✅ 适配：使用新的 getConversations，它返回包含快照的 Map
      final rawSessions = await db.getConversations();

      List<ChatSession> list = [];
      for (var map in rawSessions) {
        // 手动映射：因为现在的 conversations 表直接包含了 peer_name, peer_avatar
        // 我们不需要再查 User 表了，极快！

        // 构造一个临时的 User 对象给 UI 使用
        User tempUser = User(
          id: map['peer_id'] ?? 0,
          username: "user_${map['peer_id']}", // 占位
          nickname: map['peer_name'] ?? "未知用户",
          avatarUrl: map['peer_avatar'],
          token: "", // 不需要
        );

        list.add(
          ChatSession(
            conversationId: map['conversation_id'],
            otherUserId: map['peer_id'] ?? 0,
            lastMessage: map['last_message'] ?? "",
            lastUpdatedAt: DateTime.parse(map['last_updated_at']),
            unreadCount: map['unread_count'] ?? 0,
            lastSenderId: 0, // 新表中此字段可选，UI如果不需要判断"是否我最后发"可忽略
            otherUser: tempUser, // 直接赋值
          ),
        );
      }

      sessions.assignAll(list);
      _hasLoadedOnce = true;
    } finally {
      if (isLoading.value) isLoading(false);
    }
  }

  Future<void> fetchAllUsers() async {
    int? myId = storage.getUserId();
    if (myId == null) return;
    // 获取通讯录列表
    final users = await db.getAllUsersExcept(myId);
    allUsers.assignAll(users);
  }

  void startChatWithUser(User user) {
    int? myId = storage.getUserId();
    if (myId == null) return;

    // 使用 DbService 中统一的 ID 生成逻辑
    String convId = db.getConversationId(myId, user.id);

    Get.toNamed(
      '/chat_detail',
      arguments: {
        'otherUserId': user.id,
        'conversationId': convId,
        'otherUser': user,
      },
    )?.then((_) {
      loadSessions();
    });
  }
}
