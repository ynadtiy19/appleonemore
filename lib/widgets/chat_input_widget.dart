import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';

import '../models/sticker_model.dart';

class ChatInputWidget extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final Function(StickerItem) onSendSticker;
  final VoidCallback onImagePick;
  final List<StickerItem> stickers;
  final bool isSending;
  final bool isAiMode;
  final VoidCallback onToggleAiMode;

  const ChatInputWidget({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onSendSticker,
    required this.onImagePick,
    required this.stickers,
    required this.isSending,
    required this.isAiMode,
    required this.onToggleAiMode,
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
    if (_setIds.isNotEmpty && _currentSetIndex >= _setIds.length) {
      _currentSetIndex = 0;
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
    return Container(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [_buildInputBox(), if (_isStickerOpen) _buildStickerPanel()],
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
                // 🔥 1. AI 对话开关按钮 (放在最前面或加号后面)
                IconButton(
                  tooltip: widget.isAiMode ? "关闭 AI 助手" : "开启 AI 助手",
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedAiChat02,
                    size: 28,
                    color: widget.isAiMode
                        ? Colors.amber
                        : const Color(0xFF999999),
                  ),
                  onPressed: widget.onToggleAiMode,
                ),

                // 2. 加号按钮
                IconButton(
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedFileAdd,
                    size: 28,
                    color: const Color(0xFF999999),
                  ),
                  onPressed: widget.isSending ? null : widget.onImagePick,
                ),

                IconButton(
                  icon: HugeIcon(
                    icon: _isStickerOpen
                        ? HugeIcons.strokeRoundedSmile
                        : HugeIcons.strokeRoundedCameraSmile01,
                    size: 28,
                    color: _isStickerOpen
                        ? Colors.amber
                        : const Color(0xFF999999),
                  ),
                  onPressed: _toggleSticker,
                ),

                const Spacer(),

                // 4. 发送按钮
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
      size: 28,
      color: hasText
          ? (widget.isAiMode ? Colors.deepPurpleAccent : Colors.deepPurple)
          : const Color(0xFFCCCCCC),
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
                        placeholder: (context, url) => const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 1,
                              color: Colors.blueAccent,
                            ),
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
