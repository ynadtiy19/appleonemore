import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../models/chat_msg_model.dart';
import '../models/sticker_model.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/frontend_chat_service.dart';
import '../services/storage_service.dart';
import '../services/third_party_ai_service.dart';
import '../widgets/ChatBubble.dart';
import '../widgets/chat_input_widget.dart';
import 'user_profile_page.dart'; // ✅ 引入用户个人主页

// --- 群聊控制器 ---
class GroupChatController extends GetxController {
  final DbService _db = Get.find();
  final FrontendChatService _chatService = Get.find();
  final StorageService _storage = Get.find();

  // ✅ 1. 注入 AI 服务
  final ThirdPartyAiService _aiService = Get.put(ThirdPartyAiService());

  // 群聊列表
  final RxList<ChatMsgModel> messages = <ChatMsgModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isSending = false.obs;

  final String botName = "Gemini";
  final int botId = 999999;

  final RxBool isAiMode = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadHistory();

    // 🔥 监听全局群聊消息
    ever(_chatService.incomingGroupMessage, (ChatMsgModel? msg) {
      if (msg != null) {
        messages.insert(0, msg);
      }
    });
  }

  Future<void> loadHistory() async {
    final history = await _db.getGroupMessages(limit: 50);
    messages.assignAll(history);
    isLoading.value = false;
  }

  void toggleAiMode() {
    isAiMode.value = !isAiMode.value;
    HapticFeedback.selectionClick();
  }

  // 发送群消息
  Future<void> sendMessage(String content, {int type = 1}) async {
    if (content.trim().isEmpty || isSending.value) return;

    isSending.value = true;

    final List<ChatMsgModel> contextForAi = List.from(messages);
    final bool triggerAi = isAiMode.value;
    try {
      // 发送群聊消息: 接收者设为 0，ID设为全局群ID
      await _chatService.sendMessage(
        content: content,
        receiverId: 0,
        receiverAtsign: "@group", // 后台可根据此广播
        conversationId: FrontendChatService.groupConversationId,
        type: type,
      );

      // 发送成功后刷新列表 (因为 sendMessage 内部已存库)
      await loadHistory();
      if (triggerAi) {
        _processAiResponse(content, contextForAi);
      }
    } finally {
      isSending.value = false;
    }
  }

  Future<void> _processAiResponse(
    String userPrompt,
    List<ChatMsgModel> history,
  ) async {
    print("🤖 用户 提问: $userPrompt");
    print("历史数据：${history.map((e) => e.toJson()).toList()}");

    String? aiReply = await _aiService.fetchReply(
      currentInput: userPrompt,
      history: history,
      botName: botName,
    );

    if (aiReply != null && aiReply.isNotEmpty) {
      print("🤖 AI 回复: $aiReply");

      await _sendBotMessageAsProxy(aiReply);
    }
  }

  // ✅ 5. 特殊方法：当前用户作为代理发送机器人的消息
  Future<void> _sendBotMessageAsProxy(String content) async {
    // 注意：这里我们调用底层的 _chatService 发送消息
    // 但是，通常 P2P 协议会强制使用你的真实身份签名。
    // 所以，群里的其他人看到的发送者依然是"你"。
    // 为了解决这个问题，通常的做法是定义一个 type = 3 (代表 Bot 消息)

    // 我们复用现有的 sendMessage，但 type 设为 3 (假设 3 是 AI 消息)
    // 需要去 ChatMsgModel 和 UI 解析处适配 type=3
    await _chatService.sendMessage(
      content: content,
      receiverId: 0,
      receiverAtsign: "@group",
      conversationId: FrontendChatService.groupConversationId,
      type: 3,
    );

    await loadHistory();
  }

  void sendSticker(StickerItem sticker) {
    sendMessage("[IMAGE]${sticker.stickerUrl}[/IMAGE]", type: 2);
  }

  void sendImage(String imageUrl) {
    sendMessage("[IMAGE]$imageUrl[/IMAGE]", type: 2);
  }

  void clearMessages() {
    messages.clear();
  }
}

// --- 群聊页面 ---
class GroupChatPage extends StatefulWidget {
  const GroupChatPage({super.key});

  @override
  State<GroupChatPage> createState() => _GroupChatPageState();
}

class _GroupChatPageState extends State<GroupChatPage> {
  // 注入控制器
  final GroupChatController controller = Get.put(GroupChatController());

  final TextEditingController _textC = TextEditingController();
  final ScrollController _scrollC = ScrollController();

  List<StickerItem> _stickers = [];

  @override
  void initState() {
    super.initState();
    _loadStickers();
  }

  Future<void> _loadStickers() async {
    final res = await ApiService.fetchStickers();
    if (mounted) setState(() => _stickers = res);
  }

  void _goToUserProfile(int userId, String userName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            UserProfilePage(userId: userId, userName: userName),
      ),
    );
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();

    // 1. 选择图片
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );

    if (xFile == null) return;

    if (!mounted) return;

    try {
      // 3. 调用 ApiService 上传
      final url = await ApiService.uploadImage(File(xFile.path));

      if (url != null && url.isNotEmpty) {
        // 4. 上传成功，通过 Controller 发送消息
        controller.sendImage(url);
      } else {
        // 上传失败提示
        Get.snackbar(
          "上传失败",
          "图片上传服务暂时不可用",
          backgroundColor: Colors.red.withOpacity(0.2),
          colorText: Colors.red,
        );
      }
    } catch (e) {
      debugPrint("上传流程错误: $e");
    } finally {
      // if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: const Key('GroupChatPage_visibility'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction == 1.0) {
          // controller.loadHistory();
          //消除焦点
          // FocusManager.instance.primaryFocus?.unfocus();
        }
      },
      child: Scaffold(
        backgroundColor: const Color.fromRGBO(244, 247, 254, 1),
        appBar: _buildAppBar(),
        body: Column(
          children: [
            Expanded(child: _buildMessageList()),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      foregroundColor: Colors.black87,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '世界频道',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '全员在线',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // IconButton(
        //   icon: const HugeIcon(
        //     icon: HugeIcons.strokeRoundedComment01,
        //     size: 20.0,
        //     color: Colors.black,
        //   ),
        //   onPressed: () {
        //     Navigator.push(
        //       context,
        //       MaterialPageRoute(builder: (context) => const ChatPage()),
        //     );
        //   },
        //   tooltip: 'Ai聊天列表',
        // ),
      ],
    );
  }

  Widget _buildMessageList() {
    return Obx(() {
      if (controller.isLoading.value) {
        return const Center(
          child: CircularProgressIndicator(color: Colors.blueAccent),
        );
      }

      final messages = controller.messages;
      final myId = Get.find<StorageService>().getUserId();

      return ListView.builder(
        controller: _scrollC,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        itemCount: messages.length,
        itemBuilder: (_, index) {
          final msg = messages[index];
          final isMe = msg.senderId == myId;

          // ✅ 使用构建函数构建带头像的气泡
          return _buildGroupChatItem(msg, isMe);
        },
      );
    });
  }

  // 🔥 核心：构建群聊单条消息项 (头像 + 昵称 + 气泡)
  Widget _buildGroupChatItem(ChatMsgModel msg, bool isMe) {
    // ✅ 判定是否为 AI 消息 (Type == 3)
    bool isAi = msg.type == 3;

    // 如果是 AI 消息，即使是我发的代理消息，也不应该显示在右边，而应该显示在左边
    // 并且头像和名字要是机器人的
    if (isAi) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white,
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.grey.withOpacity(0.1),
                    width: 0.5,
                  ),
                ),
                padding: const EdgeInsets.all(4),
                child: SvgPicture.asset(
                  'images/gemini.svg',
                  fit: BoxFit.contain,
                  // width: 20,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      "Gemini",
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.purple,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  // AI 气泡
                  ChatBubble(
                    content: msg.content,
                    isMe: false, // 强制显示在左侧
                    isRead: true,
                    onVisible: () {},
                    // 可以给 Bubble 加个特殊颜色参数，如果 ChatBubble 支持的话
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 2),
                    child: Text(
                      "回复给 ${msg.senderName}",
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // 头像组件
    Widget avatar = GestureDetector(
      onTap: () => _goToUserProfile(msg.senderId, msg.senderName),
      child: CircleAvatar(
        radius: 18,
        backgroundColor: Colors.grey.shade200,
        backgroundImage: (msg.senderAvatar.isNotEmpty)
            ? NetworkImage(msg.senderAvatar)
            : null,
        child: (msg.senderAvatar.isEmpty)
            ? Text(
                msg.senderName.isNotEmpty
                    ? msg.senderName[0].toUpperCase()
                    : "?",
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              )
            : null,
      ),
    );

    if (isMe) {
      // --- 我发的消息 (右侧) ---
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 气泡
            Flexible(
              child: ChatBubble(
                content: msg.content,
                isMe: true,
                isRead: true, // 群聊默认已读
                onVisible: () {},
              ),
            ),
            const SizedBox(width: 8),
            // 头像
            avatar,
          ],
        ),
      );
    } else {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头像
            avatar,
            const SizedBox(width: 8),
            // 昵称 + 气泡
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 昵称 (可点击)
                  GestureDetector(
                    onTap: () => _goToUserProfile(msg.senderId, msg.senderName),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 4),
                      child: Text(
                        msg.senderName,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                  // 气泡
                  ChatBubble(
                    content: msg.content,
                    isMe: false,
                    isRead: true,
                    onVisible: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildInputArea() {
    return Obx(
      () => ChatInputWidget(
        controller: _textC,
        onSend: () {
          controller.sendMessage(_textC.text);
          _textC.clear();
        },
        onSendSticker: (sticker) => controller.sendSticker(sticker),
        onImagePick: _sendImage, // 暂未实现图片上传
        stickers: _stickers,
        isSending: controller.isSending.value,
        isAiMode: controller.isAiMode.value,
        onToggleAiMode: controller.toggleAiMode,
      ),
    );
  }
}
