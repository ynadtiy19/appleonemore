import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart'; // 📦 需要引入 photo_view
import 'package:visibility_detector/visibility_detector.dart';

import '../services/api_service.dart';

class ChatBubble extends StatelessWidget {
  final String content;
  final bool isMe;
  final bool isRead;
  final VoidCallback onVisible;

  const ChatBubble({
    super.key,
    required this.content,
    required this.isMe,
    required this.isRead,
    required this.onVisible,
  });

  bool get _isImage =>
      content.startsWith('[IMAGE]') && content.endsWith('[/IMAGE]');
  String get _imageUrl => content.substring(7, content.length - 8);

  @override
  Widget build(BuildContext context) {
    final shouldDetect = !isMe && !isRead;

    Widget bubbleContent = _buildBubbleUI(context);

    if (shouldDetect) {
      return VisibilityDetector(
        key: Key("msg_${content.hashCode}"),
        onVisibilityChanged: (info) {
          if (info.visibleFraction > 0.5) {
            onVisible();
          }
        },
        child: bubbleContent,
      );
    }

    return bubbleContent;
  }

  // ✨ 构建单个现代风格的按钮
  Widget _buildModernActionItem({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    bool isDestructive = false, // 是否是破坏性/取消操作
    bool showDivider = false, // 是否显示底部分割线
  }) {
    return Material(
      color: Colors.transparent, // 保持透明以透出背景色
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.black.withOpacity(0.05), // 淡淡的水波纹
        highlightColor: Colors.black.withOpacity(0.03),
        child: Container(
          height: 56, // 增加高度，更适合手指点击
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(
                    bottom: BorderSide(
                      color: Colors.grey.withOpacity(0.15),
                      width: 0.5,
                    ),
                  )
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center, // 内容居中更现代
            children: [
              // 图标
              Icon(
                icon,
                size: 22,
                color: isDestructive
                    ? const Color(0xFFFF3B30)
                    : const Color(0xFF007AFF),
              ),
              const SizedBox(width: 12),
              // 文本
              Text(
                title,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: isDestructive ? FontWeight.w600 : FontWeight.w400,
                  color: isDestructive
                      ? const Color(0xFFFF3B30)
                      : const Color(0xFF333333),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBubbleActionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // 背景透明
      elevation: 0,
      isScrollControlled: true, // 允许自适应高度
      builder: (BuildContext ctx) {
        return Container(
          margin: const EdgeInsets.only(
            left: 16,
            right: 16,
            bottom: 34,
          ), // 底部留出安全距离
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // --- 第一组：功能按钮 ---
              ClipRRect(
                borderRadius: BorderRadius.circular(20), // 大圆角
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), // 磨砂效果
                  child: Container(
                    color: Colors.white.withOpacity(0.92), // 略微半透明的白色
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildModernActionItem(
                          icon: _isImage
                              ? Icons.image_outlined
                              : Icons.copy_rounded,
                          title: _isImage ? '保存图片' : '复制文本', // 稍微改了一下文案更符合直觉
                          showDivider: _isImage, // 如果是图片，下面还有一项，所以显示分割线
                          onTap: () async {
                            Navigator.pop(ctx);
                            if (_isImage) {
                              await ApiService.copyImageFromUrl(_imageUrl);
                            } else {
                              await ApiService.copyText(content);
                            }

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(_isImage ? '图片已保存' : '文本已复制'),
                                  behavior: SnackBarBehavior
                                      .floating, // 悬浮式 SnackBar 更美观
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                          },
                        ),

                        if (_isImage)
                          _buildModernActionItem(
                            icon: Icons.link_rounded,
                            title: '复制链接',
                            showDivider: false,
                            onTap: () async {
                              Navigator.pop(ctx);
                              await ApiService.copyText(_imageUrl);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('链接已复制'),
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12), // 分组间距
              // --- 第二组：取消按钮 ---
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    color: Colors.white.withOpacity(0.92),
                    child: _buildModernActionItem(
                      icon: Icons.close_rounded,
                      title: '取消',
                      isDestructive: true, // 红色高亮
                      showDivider: false,
                      onTap: () => Navigator.pop(ctx),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBubbleUI(BuildContext context) {
    return GestureDetector(
      onLongPress: () {
        _showBubbleActionSheet(context);
      },
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            // CircleAvatar(...),
            // const SizedBox(width: 8),
          ],

          Flexible(
            child: Container(
              margin: isMe
                  ? const EdgeInsets.only(left: 60)
                  : const EdgeInsets.only(right: 60),
              // 图片模式下减少内边距，让图片撑满圆角
              padding: _isImage
                  ? const EdgeInsets.all(2)
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF4A6CF7) : Colors.white,
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
              ),
              child: _isImage
                  ? _buildImageContent(context)
                  : Text(
                      content,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.4,
                        color: isMe ? Colors.white : const Color(0xFF333333),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageContent(BuildContext context) {
    // 使用 Hero 动画连接气泡和全屏页
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ImagePreviewPage(imageUrl: _imageUrl),
          ),
        );
      },
      child: Hero(
        tag: _imageUrl + DateTime.now().toString(), // 确保 tag 唯一，或者使用消息ID
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(
            _imageUrl,
            fit: BoxFit.cover,
            width: 200,
            loadingBuilder: (_, child, p) {
              if (p == null) return child;
              return Container(
                width: 200,
                height: 150,
                color: Colors.grey[100],
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 200,
                height: 100,
                color: Colors.grey[200],
                child: const Icon(Icons.broken_image, color: Colors.grey),
              );
            },
          ),
        ),
      ),
    );
  }
}

// =========================================================
// 📸 新增：图片全屏预览页 (支持双指缩放)
// =========================================================
class ImagePreviewPage extends StatelessWidget {
  final String imageUrl;

  const ImagePreviewPage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // 全屏查看通常是黑色背景
      // Appbar 可选，通常全屏查看是沉浸式的
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      extendBodyBehindAppBar: true, // 让图片延伸到顶部
      body: Center(
        child: Hero(
          tag: imageUrl, // 对应 ChatBubble 里的 tag
          child: PhotoView(
            imageProvider: NetworkImage(imageUrl),
            // 设置背景色为透明，以便看到 Scaffold 的黑色背景
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            // 最小缩放
            minScale: PhotoViewComputedScale.contained,
            // 最大缩放
            maxScale: PhotoViewComputedScale.covered * 2.5,
            // 加载时的占位
            loadingBuilder: (context, event) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
            // 错误处理
            errorBuilder: (context, error, stackTrace) => const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image, color: Colors.white, size: 50),
                SizedBox(height: 8),
                Text("图片加载失败", style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
