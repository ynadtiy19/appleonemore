import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';

// 请确保引入了您项目中的这些文件
import '../models/AiRequestModel.dart';
import '../models/sticker_model.dart';
import '../services/api_service.dart'; // 用于上传图片/获取表情
import '../services/frontend_chat_service.dart'; // 引用 FrontendChatService
import '../services/storage_service.dart'; // 引用 StorageService
import '../widgets/app_toast.dart';

enum MessageType { text, image, sticker }

class AIChatMessage {
  final String id;
  final String content;
  final bool isMe; // true=我, false=AI
  final MessageType type;
  final int timestamp;
  final bool isSending; // 发送状态

  AIChatMessage({
    required this.id,
    required this.content,
    required this.isMe,
    required this.type,
    required this.timestamp,
    this.isSending = false,
  });

  AIChatMessage copyWith({bool? isSending}) {
    return AIChatMessage(
      id: id,
      content: content,
      isMe: isMe,
      type: type,
      timestamp: timestamp,
      isSending: isSending ?? this.isSending,
    );
  }
}

// =========================================================
// 2. AI 聊天控制器
// =========================================================
class AIChatController extends GetxController {
  // 依赖注入 FrontendChatService
  final FrontendChatService _chatService = Get.find<FrontendChatService>();

  // 🔥 修复: 注入 StorageService 以获取 userId
  final StorageService _storage = Get.find<StorageService>();

  // 🔥 修复: 初始化 GetConnect 用于 HTTP 请求
  final GetConnect _connect = GetConnect();

  // 服务器地址配置 (请替换为您实际部署的 Dart Frog 地址)
  static const String _serverBaseUrl =
      'https://appleonemorechatwithu.globeapp.dev';

  // 状态变量
  final RxList<AIChatMessage> messages = <AIChatMessage>[].obs;
  final RxBool isSending = false.obs;

  //是否开启多轮历史对话
  final RxBool isHistoryMode = false.obs;
  // 是否允许发送图片/表情 (UI控制)
  final RxBool showMediaInputs = true.obs;

  @override
  void onInit() {
    super.onInit();
    // 监听来自 Service 的 AI 回复
    ever(_chatService.incomingAiResponse, _handleAiResponse);

    // 初始化时加载历史记录
    loadHistory();
  }

  /// 加载历史记录
  Future<void> loadHistory() async {
    // 假设路由已经配置好，如果是直接在 onRequest 处理，则路径可能是 / 或 /ai_chat
    // 这里假设您的 Dart Frog 路由是根路径或根据您的实际路由文件修改
    const url = '$_serverBaseUrl/ai_chat';

    try {
      final userId = _storage.getUserId();
      if (userId == null) return;

      final response = await _connect.post(url, {
        "action": "GET_AI_HISTORY",
        "payload": {
          "user_identifier": userId.toString(),
          "limit": 50,
          "offset": 0,
        },
      });

      if (response.statusCode == 200) {
        final body = response.body; // GetConnect 自动解析 JSON
        // 确保 body 是 Map 且包含 data
        if (body is Map && body['data'] is List) {
          final List data = body['data'];

          // 转换数据并加入 messages 列表
          final historyMsgs = data.map((item) {
            return AIChatMessage(
              id: item['id'].toString(),
              content: item['content'] ?? '',
              isMe: item['is_user'] == 1, // 数据库存的是 1/0
              type: MessageType.text, // 目前数据库只存了文本
              timestamp: DateTime.parse(
                item['created_at'],
              ).millisecondsSinceEpoch,
            );
          }).toList();

          // 数据库取出来如果是按时间倒序（最新的在前），则直接使用
          // 如果是正序（最旧的在前），且 UI 是 reverse: true，则需要倒序
          // 假设 SQL 是 ORDER BY created_at ASC，我们需要反转以适配 ListView reverse
          messages.assignAll(historyMsgs.reversed.toList());
        }
      }
    } catch (e) {
      debugPrint("Failed to load history: $e");
    }
  }

  /// 远程清空历史记录
  Future<void> clearHistoryRemote() async {
    const url = '$_serverBaseUrl/ai_chat';

    try {
      final userId = _storage.getUserId();
      if (userId == null) return;

      await _connect.post(url, {
        "action": "DELETE_AI_HISTORY",
        "payload": {"user_identifier": userId.toString()},
      });

      // 清空本地 UI
      messages.clear();
    } catch (e) {
      debugPrint("Failed to clear history: $e");
    }
  }

  /// 处理接收到的 AI 消息
  void _handleAiResponse(AiResponseModel? response) {
    if (response == null) return;

    // 1. 找到对应的请求消息（通过 requestId 匹配，如果有需要更新状态的话）
    // 这里我们直接将回复添加进列表
    final aiMsg = AIChatMessage(
      id: "ai_${DateTime.now().millisecondsSinceEpoch}",
      content: response.responseText,
      isMe: false,
      type: MessageType.text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    messages.insert(0, aiMsg);

    // 如果之前有正在发送的状态，可以在这里通过 requestId 找到并置为 false
    isSending.value = false;
  }

  /// 发送文本消息
  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;

    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    isSending.value = true;

    // 1. 用户消息立即上屏
    final userMsg = AIChatMessage(
      id: tempId,
      content: text,
      isMe: true,
      type: MessageType.text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isSending: true,
    );
    messages.insert(0, userMsg);

    // 2. 准备历史记录 (如果开启了历史模式)
    List<Map<String, dynamic>> history = [];
    if (isHistoryMode.value) {
      history = _buildHistoryForGemini();
    }

    // 3. 调用 Service 发送
    // requestId 使用 tempId，方便后续匹配
    bool success = await _chatService.sendAiMessage(
      content: text,
      history: history,
      // customApiKey: "YOUR_KEY_IF_NEEDED",
    );

    if (success) {
      // 更新消息状态为已发送 (UI上去除 loading)
      _updateMessageStatus(tempId, isSending: false);
    } else {
      isSending.value = false;
      _updateMessageStatus(tempId, isSending: false);
      AppToast.show(Get.context!, message: "发送失败，请检查连接", type: ToastType.error);
    }
  }

  /// 发送图片 (仅本地展示 + 上传，AI 暂不支持多模态输入的话仅作为记录)
  Future<void> sendImage(String imageUrl) async {
    final msg = AIChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: imageUrl,
      isMe: true,
      type: MessageType.image,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    messages.insert(0, msg);
    // 如果 AI 支持图片，可以在这里调用 sendAiMessage 并附带 image url
  }

  /// 发送表情
  Future<void> sendSticker(StickerItem sticker) async {
    final msg = AIChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: sticker.stickerUrl ?? "",
      isMe: true,
      type: MessageType.sticker,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    messages.insert(0, msg);
  }

  /// 删除单条消息
  void deleteMessage(AIChatMessage msg) {
    messages.remove(msg);
  }

  /// 清空所有消息 (本地+远程)
  void clearMessages() {
    // 调用远程清除
    clearHistoryRemote();
  }

  /// 切换历史模式
  void toggleHistoryMode() {
    isHistoryMode.value = !isHistoryMode.value;
    final status = isHistoryMode.value ? "开启" : "关闭";
    AppToast.show(Get.context!, message: "多轮对话已$status");
  }

  void _updateMessageStatus(String id, {required bool isSending}) {
    final index = messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      messages[index] = messages[index].copyWith(isSending: isSending);
      messages.refresh(); // 强制刷新列表
    }
  }

  /// 构建 Gemini 格式的历史记录
  /// 将本地 AIChatMessage 转换为 API 需要的 List<Map>
  List<Map<String, dynamic>> _buildHistoryForGemini() {
    // Gemini 格式: { "role": "user"|"model", "parts": [{"text": "..."}] }
    // 注意：Gemini 对话顺序必须是 user -> model -> user -> model
    // 且我们列表是倒序的 (index 0 是最新)，需要反转

    final List<Map<String, dynamic>> history = [];

    // 取最近 20 条，避免 token 超限，且排除 sticker/image
    final validMessages = messages
        .where((m) => m.type == MessageType.text && !m.isSending)
        .take(20)
        .toList()
        .reversed // 转为正序：旧 -> 新
        .toList();

    for (var msg in validMessages) {
      history.add({
        "role": msg.isMe ? "user" : "model",
        "parts": [
          {"text": msg.content},
        ],
      });
    }
    return history;
  }
}

// =========================================================
// 3. 聊天页面 UI
// =========================================================
class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final AIChatController controller = Get.put(AIChatController());
  final TextEditingController _textC = TextEditingController();
  final ScrollController _scrollC = ScrollController();

  // 表情列表状态
  List<StickerItem> _stickers = [];

  @override
  void initState() {
    super.initState();
    _loadStickers();
  }

  Future<void> _loadStickers() async {
    // 假设 ApiService 依然可用
    try {
      final res = await ApiService.fetchStickers();
      if (!mounted) return;
      setState(() => _stickers = res);
    } catch (e) {
      debugPrint("Load stickers failed: $e");
    }
  }

  // 发送逻辑
  Future<void> _handleSendText() async {
    final text = _textC.text.trim();
    if (text.isEmpty) return;

    _textC.clear();
    await controller.sendTextMessage(text);
    _scrollToBottom();
  }

  Future<void> _handleSendSticker(StickerItem sticker) async {
    await controller.sendSticker(sticker);
    _scrollToBottom();
  }

  Future<void> _handleSendImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (xFile == null) return;

    AppToast.show(context, message: '正在上传图片...');
    // 调用原有 Service 上传
    try {
      final url = await ApiService.uploadImage(File(xFile.path));
      if (url != null) {
        await controller.sendImage(url);
        _scrollToBottom();
      } else {
        AppToast.show(context, message: '上传失败', type: ToastType.error);
      }
    } catch (e) {
      AppToast.show(context, message: '上传出错: $e', type: ToastType.error);
    }
  }

  void _scrollToBottom() {
    if (_scrollC.hasClients) {
      // 稍微延迟等待列表渲染
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollC.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  // 清空聊天确认
  void _confirmClearMessages() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('清空记录'),
          content: const Text('确定要清空当前所有对话记录吗？此操作将同时删除服务器端历史。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () {
                controller.clearMessages();
                Navigator.pop(ctx);
              },
              child: const Text('清空', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromRGBO(244, 247, 254, 1),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          // 输入区域，使用 Obx 监听 controller 状态变化
          Obx(
            () => ChatInputWidget(
              controller: _textC,
              onSend: _handleSendText,
              onSendSticker: _handleSendSticker,
              onImagePick: _handleSendImage,
              stickers: _stickers,
              isSending: controller.isSending.value,

              // 🔥 新增参数绑定
              showMediaIcons: controller.showMediaInputs.value,
              isHistoryMode: controller.isHistoryMode.value,
              onToggleHistory: controller.toggleHistoryMode,
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0.5,
      foregroundColor: Colors.black87,
      title: Obx(
        () => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gemini AI',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    // 如果正在发送，显示橙色，否则绿色
                    color: controller.isSending.value
                        ? Colors.orange
                        : Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  controller.isSending.value ? '思考中...' : '在线',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        // 清除历史按钮
        IconButton(
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedDelete02,
            size: 20.0,
            color: Colors.black54,
          ),
          onPressed: _confirmClearMessages,
          tooltip: '清空聊天',
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildMessageList() {
    return Obx(() {
      final messages = controller.messages;
      if (messages.isEmpty) {
        return const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedAiChat02,
                size: 48,
                color: Colors.grey,
              ),
              SizedBox(height: 16),
              Text("开始与 AI 对话吧", style: TextStyle(color: Colors.grey)),
            ],
          ),
        );
      }

      return ListView.builder(
        controller: _scrollC,
        reverse: true, // 倒序排列
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        itemCount: messages.length,
        itemBuilder: (_, index) {
          final msg = messages[index];
          return ChatBubble(
            message: msg,
            onDelete: () => controller.deleteMessage(msg),
          );
        },
      );
    });
  }
}

// =========================================================
// 4. 增强版输入组件 (支持历史开关 & 媒体隐藏)
// =========================================================
class ChatInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final Function(StickerItem) onSendSticker;
  final VoidCallback onImagePick;
  final List<StickerItem> stickers;
  final bool isSending;

  // 🔥 新增控制参数
  final bool showMediaIcons; // 是否显示图片/表情入口
  final bool isHistoryMode; // 是否开启历史
  final VoidCallback onToggleHistory; // 切换历史回调

  const ChatInputWidget({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onSendSticker,
    required this.onImagePick,
    required this.stickers,
    required this.isSending,
    this.showMediaIcons = true,
    required this.isHistoryMode,
    required this.onToggleHistory,
  });

  @override
  State<ChatInputWidget> createState() => _ChatInputWidgetState();
}

class _ChatInputWidgetState extends State<ChatInputWidget> {
  final FocusNode _focusNode = FocusNode();
  bool _isStickerOpen = false;
  int _currentSetIndex = 0;
  late PageController _pageController;

  final Map<String, List<StickerItem>> _groupedStickers = {};
  final List<String> _setIds = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _groupStickers();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _isStickerOpen) {
        setState(() => _isStickerOpen = false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant ChatInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stickers != widget.stickers) {
      _groupStickers();
    }
  }

  void _onTextChanged() => setState(() {});

  void _groupStickers() {
    _groupedStickers.clear();
    _setIds.clear();
    for (var item in widget.stickers) {
      if (!_groupedStickers.containsKey(item.stickerSetId)) {
        _groupedStickers[item.stickerSetId] = [];
        _setIds.add(item.stickerSetId);
      }
      _groupedStickers[item.stickerSetId]!.add(item);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    _pageController.dispose();
    super.dispose();
  }

  void _toggleSticker() {
    if (_isStickerOpen) {
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
      Future.delayed(const Duration(milliseconds: 150), () {
        setState(() => _isStickerOpen = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // 如果 showMediaIcons 为 false，强制关闭表情面板
    if (!widget.showMediaIcons && _isStickerOpen) {
      _isStickerOpen = false;
    }

    return Container(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildInputBox(),
          // 只有允许媒体输入时才渲染表情面板
          if (widget.showMediaIcons && _isStickerOpen) _buildStickerPanel(),
        ],
      ),
    );
  }

  Widget _buildInputBox() {
    final bool hasText = widget.controller.text.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: const Color(0xFFE0E0E0), width: 0.5),
      ),
      child: Column(
        children: [
          TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            maxLines: 5,
            minLines: 1,
            style: const TextStyle(fontSize: 16, color: Colors.black87),
            decoration: const InputDecoration(
              hintText: "输入消息...",
              hintStyle: TextStyle(color: Color(0xFFAAAAAA), fontSize: 16),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              border: InputBorder.none,
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                // 🔥 1. 历史记录开关 (始终显示或根据需求)
                IconButton(
                  tooltip: widget.isHistoryMode ? "关闭连续对话" : "开启连续对话",
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedTime02, // 时钟图标
                    size: 24,
                    color: widget.isHistoryMode
                        ? Colors
                              .deepPurple // 激活状态颜色
                        : const Color(0xFF999999), // 关闭状态颜色
                  ),
                  onPressed: widget.onToggleHistory,
                ),

                // 🔥 2. 媒体按钮 (根据 showMediaIcons 决定是否显示)
                if (widget.showMediaIcons) ...[
                  IconButton(
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: Color(0xFF999999),
                      size: 28,
                    ),
                    onPressed: widget.isSending ? null : widget.onImagePick,
                  ),
                  IconButton(
                    icon: Icon(
                      _isStickerOpen
                          ? Icons.keyboard_hide_outlined
                          : Icons.sticky_note_2_outlined,
                      color: _isStickerOpen
                          ? Colors.deepPurple
                          : const Color(0xFF999999),
                      size: 26,
                    ),
                    onPressed: _toggleSticker,
                  ),
                ],

                const Spacer(),

                // 🔥 3. 发送按钮
                GestureDetector(
                  onTap: (widget.isSending || !hasText) ? null : widget.onSend,
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.transparent,
                    ),
                    child: _buildSendIcon(hasText),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendIcon(bool hasText) {
    if (widget.isSending) {
      return const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.blueAccent,
        ),
      );
    }
    return HugeIcon(
      icon: HugeIcons.strokeRoundedSent,
      size: 22,
      color: hasText ? Colors.deepPurple : const Color(0xFFCCCCCC),
    );
  }

  Widget _buildStickerPanel() {
    if (_setIds.isEmpty) {
      return Container(
        height: 280,
        color: const Color(0xFFF9F9F9),
        child: const Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.blueAccent,
          ),
        ),
      );
    }

    return Container(
      height: 320,
      color: const Color(0xFFF9F9F9),
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) =>
                  setState(() => _currentSetIndex = index),
              itemCount: _setIds.length,
              itemBuilder: (context, index) {
                final String setId = _setIds[index];
                final List<StickerItem> items = _groupedStickers[setId]!;
                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                  ),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    return GestureDetector(
                      onTap: () => widget.onSendSticker(items[i]),
                      child: CachedNetworkImage(
                        imageUrl: items[i].stickerUrl,
                        fit: BoxFit.contain,
                        placeholder: (_, __) => const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 1),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            height: 54,
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _setIds.length,
              itemBuilder: (context, index) {
                final bool isSelected = _currentSetIndex == index;
                final String firstIconUrl =
                    _groupedStickers[_setIds[index]]!.first.stickerUrl;
                return GestureDetector(
                  onTap: () {
                    _pageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutQuart,
                    );
                  },
                  child: Container(
                    width: 64,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFF0F0F0)
                          : Colors.transparent,
                      border: Border(
                        right: BorderSide(
                          color: Colors.grey.withOpacity(0.1),
                          width: 0.5,
                        ),
                      ),
                    ),
                    child: CachedNetworkImage(imageUrl: firstIconUrl),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// =========================================================
// 5. 单条消息气泡 (支持长按删除)
// =========================================================
class ChatBubble extends StatelessWidget {
  final AIChatMessage message;
  final VoidCallback onDelete;

  const ChatBubble({super.key, required this.message, required this.onDelete});

  void _openImage(BuildContext context, String url) {
    if (url.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImagePreviewPage(imageUrl: url),
          fullscreenDialog: true,
        ),
      );
    }
  }

  void _onLongPress(BuildContext context) {
    HapticFeedback.mediumImpact(); // 添加震动反馈
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.type == MessageType.text)
                ListTile(
                  leading: const HugeIcon(
                    icon: HugeIcons.strokeRoundedCopy01,
                    color: Colors.black87,
                  ),
                  title: const Text('复制内容'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: message.content));
                    Navigator.pop(context);
                    AppToast.show(context, message: '已复制');
                  },
                ),
              ListTile(
                leading: const HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete02,
                  color: Colors.red,
                ),
                title: const Text('删除消息', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  onDelete();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMe = message.isMe;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8), // 增加一点垂直间距
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. AI 头像替换为 SVG
          if (!isMe) ...[
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
                  // width: 20, // 可以在这里控制大小
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],

          // 2. 消息气泡主体
          Flexible(
            child: GestureDetector(
              onTap: message.type == MessageType.image
                  ? () => _openImage(context, message.content)
                  : null,
              onLongPress: () => _onLongPress(context),
              child: Container(
                constraints: BoxConstraints(
                  // 限制最大宽度，防止气泡占满屏幕
                  maxWidth: MediaQuery.of(context).size.width * 0.82,
                ),
                padding: message.type == MessageType.text
                    ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
                    : const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isMe
                      ? const Color.fromRGBO(44, 100, 247, 1) // 用户: 蓝色背景
                      : Colors.white, // AI: 白色背景
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 5,
                      offset: const Offset(0, 2),
                    ),
                  ],
                  // AI 消息增加边框以区分白色背景
                  border: !isMe
                      ? Border.all(color: Colors.grey.withOpacity(0.15))
                      : null,
                ),
                child: _buildContent(context),
              ),
            ),
          ),

          // 3. 用户发送状态 Loading
          if (isMe && message.isSending)
            const Padding(
              padding: EdgeInsets.only(top: 12, left: 8),
              child: SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: Colors.blueAccent,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 构建消息内容
  Widget _buildContent(BuildContext context) {
    switch (message.type) {
      case MessageType.image:
      case MessageType.sticker:
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: CachedNetworkImage(
            imageUrl: message.content,
            width: 200,
            fit: BoxFit.contain,
            placeholder: (_, _) => const SizedBox(
              width: 150,
              height: 150,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ),
            errorWidget: (_, _, _) => const SizedBox(
              width: 100,
              height: 100,
              child: Icon(Icons.broken_image, color: Colors.grey),
            ),
          ),
        );

      case MessageType.text:
        if (message.isMe) {
          return Text(
            message.content,
            style: const TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.white,
            ),
          );
        } else {
          return _buildAiMarkdown(context);
        }
    }
  }

  Widget _buildAiMarkdown(BuildContext context) {
    return GptMarkdown(
      message.content,
      style: const TextStyle(fontSize: 15, height: 1.6, color: Colors.black87),
      textAlign: TextAlign.left,
      textScaler: const TextScaler.linear(1),
      useDollarSignsForLatex: true,

      highlightBuilder: (context, text, style) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: (style.fontSize ?? 15) * 0.9,
              color: const Color(0xFFE01E5A),
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      },

      latexWorkaround: (tex) {
        List<String> stack = [];
        tex = tex.splitMapJoin(
          RegExp(r"\\text\{|\{|\}|\_"),
          onMatch: (p) {
            String input = p[0] ?? "";
            if (input == r"\text{") stack.add(input);
            if (stack.isNotEmpty) {
              if (input == r"{") stack.add(input);
              if (input == r"}") stack.removeLast();
              if (input == r"_") return r"\_";
            }
            return input;
          },
        );
        return tex.replaceAllMapped(RegExp(r"align\*"), (match) => "aligned");
      },

      latexBuilder: (context, tex, textStyle, inline) {
        if (tex.contains(r"\begin{tabular}")) {
          String tableString =
              "|${(RegExp(r"^\\begin\{tabular\}\{.*?\}(.*?)\\end\{tabular\}$", multiLine: true, dotAll: true).firstMatch(tex)?[1] ?? "").trim()}|";

          tableString = tableString
              .replaceAll(r"\\", "|\n|")
              .replaceAll(r"\hline", "")
              .replaceAll(RegExp(r"(?<!\\)&"), "|");

          var tableStringList = tableString.split("\n")..insert(1, "|---|");
          tableString = tableStringList.join("\n");

          return GptMarkdown(tableString);
        }

        var controller = ScrollController();

        Widget child = Math.tex(
          tex,
          textStyle: textStyle.copyWith(color: Colors.black87),
          onErrorFallback: (err) =>
              Text(tex, style: textStyle.copyWith(color: Colors.red)),
        );

        if (!inline) {
          child = Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Scrollbar(
              controller: controller,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: child,
              ),
            ),
          );
        }

        return SelectionArea(child: child);
      },

      sourceTagBuilder: (buildContext, string, textStyle) {
        var value = int.tryParse(string);
        value ??= -1;
        value += 1;
        return Container(
          margin: const EdgeInsets.only(left: 2, right: 2, bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            "$value",
            style: const TextStyle(
              fontSize: 10,
              color: Colors.blueAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}

// =========================================================
// 6. 图片预览页
// =========================================================
class ImagePreviewPage extends StatefulWidget {
  final String imageUrl;
  const ImagePreviewPage({super.key, required this.imageUrl});
  @override
  State<ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<ImagePreviewPage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();
  late AnimationController _animationController;
  Animation<Matrix4>? _animation;
  Offset _dragOffset = Offset.zero;
  double _bgOpacity = 1.0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _animationController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addListener(() {
          _transformController.value = _animation!.value;
        });
  }

  @override
  void dispose() {
    _transformController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _onDoubleTap() {
    Matrix4 currentMatrix = _transformController.value;
    double scale = currentMatrix.getMaxScaleOnAxis();
    Matrix4 targetMatrix;
    if (scale > 1.0) {
      targetMatrix = Matrix4.identity();
    } else {
      targetMatrix = Matrix4.identity()..scale(2.0);
    }
    _animation = Matrix4Tween(begin: currentMatrix, end: targetMatrix).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward(from: 0);
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_transformController.value.getMaxScaleOnAxis() <= 1.01) {
      setState(() => _isDragging = true);
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    setState(() {
      _dragOffset += details.delta;
      double progress = (_dragOffset.dy.abs() / 300).clamp(0.0, 1.0);
      _bgOpacity = 1.0 - progress;
    });
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    setState(() => _isDragging = false);
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset.dy.abs() > 100 || velocity.abs() > 500) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _dragOffset = Offset.zero;
        _bgOpacity = 1.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.black.withOpacity(_bgOpacity)),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: _onDoubleTap,
              onVerticalDragStart: _onVerticalDragStart,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              child: Center(
                child: Transform.translate(
                  offset: _dragOffset,
                  child: InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 1.0,
                    maxScale: 4.0,
                    panEnabled: !_isDragging,
                    child: CachedNetworkImage(
                      imageUrl: widget.imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => const CircularProgressIndicator(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
