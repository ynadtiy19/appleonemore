import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';

// 假设这些文件依然存在于你的项目中，保留引用
import '../models/sticker_model.dart';
import '../services/api_service.dart';
import '../widgets/app_toast.dart';
import '../widgets/chat_input_widget.dart';
import 'chat_list_page.dart';

// =========================================================
// 1. 定义本地消息模型 (为云存储做准备)
// =========================================================
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

  // 用于复制状态但改变某些字段
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
// 2. 新增 AI 聊天控制器 (替代原有的 Service)
// =========================================================
class AIChatController extends GetxController {
  // 消息列表（响应式）
  final RxList<AIChatMessage> messages = <AIChatMessage>[].obs;

  // GetConnect 用于网络请求
  final GetConnect _connect = GetConnect();

  // API 地址
  static const String _apiUrl = "https://mydiumtify.globeapp.dev/chattext";

  @override
  void onInit() {
    super.onInit();
    // 可以在这里加载本地数据库的历史记录
    // _loadHistoryFromDb();
  }

  // 发送文本消息
  Future<void> sendTextMessage(String text) async {
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();

    // 1. 立即上屏 (本地显示)
    final userMsg = AIChatMessage(
      id: tempId,
      content: text,
      isMe: true,
      type: MessageType.text,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      isSending: true,
    );
    messages.insert(0, userMsg);

    try {
      // 2. 模拟存入本地数据库
      await _saveToLocalDb(userMsg);

      // 更新发送状态为成功
      _updateMessageStatus(tempId, isSending: false);

      // 3. 请求 AI 接口
      // 编码参数
      final response = await _connect.get(
        "$_apiUrl?q=${Uri.encodeComponent(text)}",
      );

      if (response.statusCode == 200 && response.body != null) {
        // 解析: {"isSender":false,"text":"..."}
        // 注意：GetConnect 会自动尝试 decode JSON，如果 response.body 是 Map 直接用
        final data = response.body is String
            ? jsonDecode(response.body)
            : response.body;

        final String replyText = data['text'] ?? "AI 暂时无法回答";

        // 4. AI 回复上屏
        final aiMsg = AIChatMessage(
          id: "ai_${DateTime.now().millisecondsSinceEpoch}",
          content: replyText,
          isMe: false, // data['isSender'] 也可以用，但这里肯定是 AI
          type: MessageType.text,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
        messages.insert(0, aiMsg);
        await _saveToLocalDb(aiMsg);
      } else {
        AppToast.show(
          Get.context!,
          message: "AI 连接失败: ${response.statusText}",
          type: ToastType.error,
        );
      }
    } catch (e) {
      debugPrint("API Error: $e");
      AppToast.show(Get.context!, message: "发送失败，请检查网络", type: ToastType.error);
    }
  }

  // 发送表情 (AI 可能无法识别，仅本地展示或发送文本描述)
  Future<void> sendSticker(StickerItem sticker) async {
    final msg = AIChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: sticker.stickerUrl ?? "",
      isMe: true,
      type: MessageType.sticker,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    messages.insert(0, msg);
    await _saveToLocalDb(msg);

    // 可选：发送给 AI 一个描述，让它知道你发了表情
    // sendTextMessage("[表情]");
  }

  // 发送图片
  Future<void> sendImage(String imageUrl) async {
    final msg = AIChatMessage(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: imageUrl,
      isMe: true,
      type: MessageType.image,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );
    messages.insert(0, msg);
    await _saveToLocalDb(msg);
  }

  void clearMessages() {
    messages.clear();
    // TODO: 清空数据库
    // _db.delete('messages');
  }

  // 模拟更新消息状态
  void _updateMessageStatus(String id, {required bool isSending}) {
    final index = messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      messages[index] = messages[index].copyWith(isSending: isSending);
    }
  }

  // 预留：存入本地数据库
  Future<void> _saveToLocalDb(AIChatMessage msg) async {
    // TODO: 实现 SQLite 或 Hive 存储
    // await DbService.insert(msg);
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
  // 注入新的控制器
  final AIChatController controller = Get.put(AIChatController());

  final TextEditingController _textC = TextEditingController();
  final ScrollController _scrollC = ScrollController();

  bool _isUploading = false;
  List<StickerItem> _stickers = [];

  @override
  void initState() {
    super.initState();
    _loadStickers();
  }

  Future<void> _loadStickers() async {
    final res = await ApiService.fetchStickers();
    if (!mounted) return;
    setState(() => _stickers = res);
  }

  // 发送表情
  Future<void> _sendSticker(StickerItem sticker) async {
    await controller.sendSticker(sticker);
    _scrollToBottom();
  }

  // 发送文本
  Future<void> _sendText() async {
    if (_textC.text.trim().isEmpty) return;
    final text = _textC.text.trim();
    _textC.clear();

    await controller.sendTextMessage(text);
    _scrollToBottom();
  }

  // 发送图片
  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (xFile == null) return;

    if (!mounted) return;
    setState(() => _isUploading = true);
    AppToast.show(context, message: '正在上传图片…');

    // 这里依然调用 ApiService 上传文件获取 URL
    final url = await ApiService.uploadImage(File(xFile.path));

    if (url != null) {
      await controller.sendImage(url);
      _scrollToBottom();
    } else {
      AppToast.show(context, message: '图片上传失败', type: ToastType.error);
    }

    setState(() => _isUploading = false);
  }

  void _scrollToBottom() {
    if (_scrollC.hasClients) {
      _scrollC.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  // 清空聊天
  void _clearMessages() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('清空聊天记录'),
          content: const Text('此操作将清空本地缓存的消息，确定吗？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                controller.clearMessages();
                Navigator.pop(ctx);
                AppToast.show(
                  context,
                  message: '聊天记录已清空',
                  type: ToastType.success,
                );
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
            'chat', // 修改标题
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green, // AI 永远在线
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '在线',
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
          tooltip: '好友聊天',
        ),
        const SizedBox(width: 8),
        IconButton(
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedDelete01,
            size: 20.0,
            color: Colors.black,
          ),
          onPressed: _clearMessages,
          tooltip: '清空聊天',
        ),
      ],
    );
  }

  Widget _buildMessageList() {
    return Obx(() {
      final messages = controller.messages;

      return ListView.builder(
        controller: _scrollC,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        itemCount: messages.length,
        itemBuilder: (_, index) {
          final msg = messages[index];
          return ChatBubble(message: msg);
        },
      );
    });
  }

  Widget _buildInputArea() {
    return ChatInputWidget(
      controller: _textC,
      onSend: _sendText,
      onSendSticker: _sendSticker,
      onImagePick: _sendImage,
      stickers: _stickers,
      isSending: _isUploading,
    );
  }
}

// =========================================================
// 4. 单条消息气泡 (根据 MessageType 渲染)
// =========================================================
class ChatBubble extends StatelessWidget {
  final AIChatMessage message;

  const ChatBubble({super.key, required this.message});

  void _openImage(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImagePreviewPage(imageUrl: url),
        fullscreenDialog: true,
      ),
    );
  }

  void _onLongPress(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(message.type == MessageType.text ? '复制文本' : '复制链接'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message.content));
                  Navigator.pop(context);
                  AppToast.show(context, message: '已复制');
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
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI 头像
          if (!isMe) ...[
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.indigoAccent,
              child: Icon(Icons.smart_toy, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],

          Flexible(
            child: GestureDetector(
              onTap: message.type == MessageType.image
                  ? () => _openImage(context, message.content)
                  : null,
              onLongPress: () => _onLongPress(context),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.7,
                ),
                padding: message.type == MessageType.text
                    ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                    : const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isMe
                      ? const Color.fromRGBO(44, 100, 247, 1)
                      : Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMe ? 18 : 4),
                    bottomRight: Radius.circular(isMe ? 4 : 18),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: _buildContent(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    switch (message.type) {
      case MessageType.image:
      case MessageType.sticker:
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            message.content,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.broken_image, color: Colors.grey),
            loadingBuilder: (_, child, p) => p == null
                ? child
                : const SizedBox(
                    width: 150,
                    height: 150,
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
          ),
        );
      case MessageType.text:
      default:
        return Text(
          message.content,
          style: TextStyle(
            fontSize: 15,
            height: 1.4,
            color: message.isMe ? Colors.white : Colors.black87,
          ),
        );
    }
  }
}

// =========================================================
// 5. 图片预览页 (优化手势版)
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

  // 拖动偏移量
  Offset _dragOffset = Offset.zero;
  // 背景透明度
  double _bgOpacity = 1.0;
  // 是否正在拖动关闭
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

  // 双击缩放逻辑
  void _onDoubleTap() {
    Matrix4 currentMatrix = _transformController.value;
    double scale = currentMatrix.getMaxScaleOnAxis();

    Matrix4 targetMatrix;
    if (scale > 1.0) {
      // 缩小回 1.0
      targetMatrix = Matrix4.identity();
    } else {
      // 放大到 2.0
      targetMatrix = Matrix4.identity()..scale(2.0);
    }

    _animation = Matrix4Tween(begin: currentMatrix, end: targetMatrix).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward(from: 0);
  }

  // 开始拖动
  void _onVerticalDragStart(DragStartDetails details) {
    // 只有在没有缩放（scale == 1.0）时才允许拖动关闭
    if (_transformController.value.getMaxScaleOnAxis() <= 1.01) {
      setState(() {
        _isDragging = true;
      });
    }
  }

  // 拖动中
  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;

    setState(() {
      _dragOffset += details.delta;
      // 随着拖动距离增加，透明度降低
      // 300 像素完全透明
      double progress = (_dragOffset.dy.abs() / 300).clamp(0.0, 1.0);
      _bgOpacity = 1.0 - progress;
    });
  }

  // 拖动结束
  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_isDragging) return;
    setState(() => _isDragging = false);

    // 如果拖动速度够快，或者距离够远，则关闭
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset.dy.abs() > 100 || velocity.abs() > 500) {
      Navigator.of(context).pop();
    } else {
      // 否则回弹
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
          // 1. 背景层：监听点击退出
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(color: Colors.black.withOpacity(_bgOpacity)),
            ),
          ),

          // 2. 图片层：处理手势
          Positioned.fill(
            child: GestureDetector(
              onDoubleTap: _onDoubleTap,
              // 使用 VerticalDrag 处理下拉关闭，避免和 InteractiveViewer 冲突
              onVerticalDragStart: _onVerticalDragStart,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              child: Center(
                child: Transform.translate(
                  offset: _dragOffset, // 应用拖动偏移
                  child: InteractiveViewer(
                    transformationController: _transformController,
                    minScale: 1.0,
                    maxScale: 4.0,
                    // 只有当没有正在进行"关闭拖动"时，才允许内部 Pan (缩放后的漫游)
                    panEnabled: !_isDragging,
                    child: Image.network(widget.imageUrl, fit: BoxFit.contain),
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
