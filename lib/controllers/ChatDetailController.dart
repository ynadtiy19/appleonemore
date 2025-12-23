import 'package:get/get.dart';

import '../models/chat_msg_model.dart';
import '../models/sticker_model.dart';
import '../models/user_model.dart';
import '../services/db_service.dart';
import '../services/frontend_chat_service.dart';
import '../services/storage_service.dart';

class ChatDetailController extends GetxController {
  final DbService db = Get.find();
  final FrontendChatService atService = Get.find();
  final StorageService storage = Get.find();

  late int otherUserId;
  late String conversationId;
  User? otherUser;

  // ✅ 适配：使用 ChatMsgModel 替代 Map
  var messages = <ChatMsgModel>[].obs;
  var isLoading = true.obs;
  var isSending = false.obs;

  @override
  void onInit() {
    super.onInit();
    final args = Get.arguments;
    if (args != null) {
      otherUserId = args['otherUserId'];
      conversationId = args['conversationId'];
      otherUser = args['otherUser'];
      _initChat();
    }
  }

  Future<void> _initChat() async {
    await loadHistory();

    // 进入页面即清空未读
    await db.clearUnreadCount(conversationId);

    // ✅ 适配：监听 incomingMessage (类型已变更为 ChatMsgModel)
    ever(atService.incomingMessage, (ChatMsgModel? msg) {
      if (msg == null) return;

      // 确保消息属于当前会话
      if (msg.conversationId == conversationId) {
        // 插入到列表头部
        messages.insert(0, msg);

        // 如果当前页面可见，立即标记已读
        markSingleMessageRead(msg.id);
      }
    });
  }

  Future<void> loadHistory() async {
    // ✅ 适配：db.getChatHistory 现在直接返回 List<ChatMsgModel>
    final list = await db.getChatHistory(conversationId);
    messages.assignAll(list);
    isLoading(false);
  }

  Future<void> markSingleMessageRead(String messageId) async {
    // 1. 内存中更新状态
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index != -1 && isMessageUnread(messages[index])) {
      // 这里的 Model 是 final 的，通常需要 copyWith，或者我们假定内存刷新即可
      // 简单做法：不做 Model 变更，只触发数据库更新，因为 UI 已读状态通常由 isMe 决定
      // 如果 UI 有 "对方已读" 标记，则需要复杂的逻辑。这里仅处理 "消除未读红点"。
      await db.markMessageRead(messageId);
    }
  }

  // 辅助判断
  bool isMessageUnread(ChatMsgModel msg) {
    // 这里我们假设 Db 查出来的消息如果 is_read=0 且是接收的消息
    // 由于 ChatMsgModel 简化了，我们可以通过 senderId 判断
    return msg.senderId == otherUserId;
  }

  Future<void> sendChatMessage(String content, {int type = 1}) async {
    final myId = storage.getUserId();
    if (myId == null || content.trim().isEmpty) return;
    if (isSending.value) return;

    isSending.value = true;
    try {
      String targetAtsign = otherUser?.username ?? "@unknown";

      bool success = await atService.sendMessage(
        content: content,
        receiverId: otherUserId,
        receiverAtsign: targetAtsign,
        type: type,
        conversationId: '',
      );

      if (success) {
        await loadHistory();
      }
    } finally {
      isSending.value = false;
    }
  }

  void sendSticker(StickerItem sticker) {
    sendChatMessage("[IMAGE]${sticker.stickerUrl}[/IMAGE]", type: 2);
  }

  Future<void> clearAllHistory() async {
    await db.clearChatHistory(conversationId);
    messages.clear();
  }
}
