import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';

import '../models/chat_msg_model.dart';
import '../models/sticker_model.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/frontend_chat_service.dart';
import '../services/storage_service.dart';
import '../widgets/ChatBubble.dart';
import '../widgets/chat_input_widget.dart';
import 'chat_list_page.dart';
import 'user_profile_page.dart'; // ✅ 引入用户个人主页

// --- 群聊控制器 ---
class GroupChatController extends GetxController {
  final DbService _db = Get.find();
  final FrontendChatService _chatService = Get.find();
  final StorageService _storage = Get.find();

  // 群聊列表
  final RxList<ChatMsgModel> messages = <ChatMsgModel>[].obs;
  final RxBool isLoading = true.obs;
  final RxBool isSending = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadHistory();

    // 🔥 监听全局群聊消息
    ever(_chatService.incomingGroupMessage, (ChatMsgModel? msg) {
      if (msg != null) {
        messages.insert(0, msg);
      }
    });
  }

  Future<void> _loadHistory() async {
    final history = await _db.getGroupMessages(limit: 50);
    messages.assignAll(history);
    isLoading.value = false;
  }

  // 发送群消息
  Future<void> sendMessage(String content, {int type = 1}) async {
    if (content.trim().isEmpty || isSending.value) return;

    isSending.value = true;
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
      await _loadHistory();
    } finally {
      isSending.value = false;
    }
  }

  void sendSticker(StickerItem sticker) {
    sendMessage("[IMAGE]${sticker.stickerUrl}[/IMAGE]", type: 2);
  }

  // ✅ 新增：发送图片方法的封装
  void sendImage(String imageUrl) {
    sendMessage("[IMAGE]$imageUrl[/IMAGE]", type: 2);
  }

  void clearMessages() {
    messages.clear();
    // 实际项目中可能需要删除 DB
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

  // ✅ 跳转用户主页
  void _goToUserProfile(int userId, String userName) {
    // 避免跳转到自己的主页 (可选，或者跳转到 ProfilePage)
    // 这里统一跳转到 UserProfilePage
    Get.to(() => UserProfilePage(userId: userId, userName: userName));
  }

  // ✅ 修改：完整的图片上传与发送逻辑
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
    return Scaffold(
      backgroundColor: const Color.fromRGBO(244, 247, 254, 1),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildInputArea(),
        ],
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
        IconButton(
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedComment01,
            size: 20.0,
            color: Colors.black,
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const ChatListPage()),
            );
          },
          tooltip: '私信列表',
        ),
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
      ),
    );
  }
}
