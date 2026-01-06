import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../controllers/ChatDetailController.dart';
import '../models/sticker_model.dart';
import '../services/api_service.dart';
import '../widgets/ChatBubble.dart';
import '../widgets/chat_input_widget.dart';

class ChatDetailPage extends StatefulWidget {
  const ChatDetailPage({super.key});

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  late final ChatDetailController controller;
  final TextEditingController _textC = TextEditingController();
  final ScrollController _scrollC = ScrollController();
  final GlobalKey _listKey = GlobalKey();

  List<StickerItem> _stickers = [];

  @override
  void initState() {
    super.initState();
    _initController();
    _loadStickerData();
  }

  void _initController() {
    final args = Get.arguments;
    final String conversationId = args['conversationId'];
    // 使用 conversationId 作为 tag
    controller = Get.put(ChatDetailController(), tag: conversationId);
  }

  Future<void> _loadStickerData() async {
    final res = await ApiService.fetchStickers();
    if (mounted) setState(() => _stickers = res);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F4F7),
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Column(
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
      scrolledUnderElevation: 0,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new,
          color: Colors.black87,
          size: 22,
        ),
        onPressed: () => Get.back(),
      ),
      title: Column(
        children: [
          Text(
            controller.otherUser?.nickname ?? "用户",
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                "在线",
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
      centerTitle: true,
      actions: [
        IconButton(
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedDelete01,
            color: Colors.black87,
          ),
          onPressed: () async => await controller.clearAllHistory(),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildMessageList() {
    return Obx(() {
      if (controller.isLoading.value) {
        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
      }

      final myId = controller.storage.getUserId();

      return ListView.builder(
        key: _listKey,
        controller: _scrollC,
        reverse: true, // 聊天通常是倒序的
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        itemCount: controller.messages.length,
        itemBuilder: (context, index) {
          // ✅ 适配：msg 现在是 ChatMsgModel 对象
          final msg = controller.messages[index];
          final bool isMe = msg.senderId == myId;

          // is_read 逻辑需要判断，如果是自己发的算已读，或者根据实际业务
          // 这里简化处理，接收方未读
          // 这里的 ChatMsgModel 没有 isRead 字段在 Model 定义里显示(之前的代码有)，如果 Model 里没有，默认 true
          // 假设 DbService saveMessage 存了 isRead 状态，但 Model 需要由 row 转换
          bool isRead = true;
          // 实际项目中可以在 ChatMsgModel 加一个 isRead 字段

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: ChatBubble(
              content: msg.content, // ✅ 对象属性访问
              isMe: isMe,
              isRead: isRead,
              onVisible: () {
                // 如果不是我发的，且未读，则标记
                if (!isMe) {
                  controller.markSingleMessageRead(msg.id);
                }
              },
            ),
          );
        },
      );
    });
  }

  Widget _buildInputArea() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            offset: const Offset(0, -2),
            blurRadius: 10,
          ),
        ],
      ),
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Obx(
        () => ChatInputWidget(
          controller: _textC,
          onSend: () {
            if (controller.isSending.value) return;
            if (_textC.text.trim().isNotEmpty) {
              controller.sendChatMessage(_textC.text);
              _textC.clear();
            }
          },
          onSendSticker: (sticker) => controller.sendSticker(sticker),
          onImagePick: () {},
          stickers: _stickers,
          isSending: controller.isSending.value,
          isAiMode: false,
          onToggleAiMode: () {},
        ),
      ),
    );
  }
}
