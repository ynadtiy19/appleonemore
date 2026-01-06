import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:photo_view/photo_view.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../services/api_service.dart';

class ChatBubble extends StatelessWidget {
  final String content;
  final bool isMe;
  final bool isRead;
  final VoidCallback onVisible;
  final VoidCallback? onDelete; // ✨ 新增：删除回调

  const ChatBubble({
    super.key,
    required this.content,
    required this.isMe,
    required this.isRead,
    required this.onVisible,
    this.onDelete, // 可选传参
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

  void _onLongPress(BuildContext context) {
    HapticFeedback.mediumImpact();

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
              if (!_isImage)
                ListTile(
                  leading: const HugeIcon(
                    icon: HugeIcons.strokeRoundedCopy01,
                    color: Colors.black87,
                  ),
                  title: const Text('复制内容'),
                  onTap: () {
                    // 复制逻辑
                    Clipboard.setData(ClipboardData(text: content));
                    Navigator.pop(context);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已复制'),
                        duration: Duration(milliseconds: 800),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),

              if (_isImage)
                ListTile(
                  leading: const HugeIcon(
                    icon: HugeIcons.strokeRoundedImage01,
                    color: Colors.black87,
                  ),
                  title: const Text('保存图片'),
                  onTap: () async {
                    Navigator.pop(context);
                    await ApiService.copyImageFromUrl(
                      _imageUrl,
                    ); // 假设 ApiService 有这个方法
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('图片已保存')));
                    }
                  },
                ),

              // 3. 删除消息
              ListTile(
                leading: const HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete02,
                  color: Colors.red,
                ),
                title: const Text('删除消息', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(context);
                  // 如果外部传入了 onDelete 逻辑则执行
                  if (onDelete != null) {
                    onDelete!();
                  } else {
                    debugPrint("删除功能尚未绑定");
                  }
                },
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
        _onLongPress(context);
      },
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            // 可以在这里加头像
          ],

          Flexible(
            child: Container(
              margin: isMe
                  ? const EdgeInsets.only(left: 60)
                  : const EdgeInsets.only(right: 15),
              padding: _isImage
                  ? const EdgeInsets.all(2)
                  : const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isMe ? const Color(0xFF4A6CF7) : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isMe ? 18 : 4),
                  topRight: Radius.circular(isMe ? 4 : 18),
                  bottomLeft: const Radius.circular(18),
                  bottomRight: const Radius.circular(18),
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
                  : (isMe
                        ? Text(
                            content,
                            style: const TextStyle(
                              fontSize: 15,
                              height: 1.1,
                              color: Colors.white,
                              fontFamily: 'Lato',
                              fontWeight: FontWeight.w300,
                            ),
                          )
                        : _buildAiMarkdown(context)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageContent(BuildContext context) {
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
        tag: _imageUrl + DateTime.now().toString(),
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

  // AI Markdown 渲染组件
  Widget _buildAiMarkdown(BuildContext context) {
    return GptMarkdown(
      content,
      style: const TextStyle(
        fontSize: 15,
        height: 1.6,
        color: Color(0xFF333333),
        fontFamily: 'ShantellSans',
        fontWeight: FontWeight.w300,
      ),
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

// 图片预览组件
class ImagePreviewPage extends StatelessWidget {
  final String imageUrl;

  const ImagePreviewPage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Center(
        child: Hero(
          tag: imageUrl,
          child: PhotoView(
            imageProvider: NetworkImage(imageUrl),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2.5,
            loadingBuilder: (context, event) => const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
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
