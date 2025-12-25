import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/storage_service.dart';
import '../widgets/app_toast.dart';

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final _titleC = TextEditingController();
  final _quillC = quill.QuillController.basic();
  final ScrollController _editorScrollC = ScrollController();

  bool _isSubmitting = false;

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (xFile == null) return;

    if (!mounted) return;
    AppToast.show(context, message: '正在上传图片…');

    final url = await ApiService.uploadImage(File(xFile.path));

    if (url != null) {
      _insertImageToEditor(url);
    } else {
      if (!mounted) return;
      AppToast.show(context, message: '图片上传失败', type: ToastType.error);
    }
  }

  // 插入图片/GIF 到底层逻辑
  void _insertImageToEditor(String url) {
    final index = _quillC.selection.baseOffset;
    final length = _quillC.selection.extentOffset - index;

    // 1. 插入图片
    _quillC.replaceText(index, length, quill.BlockEmbed.image(url), null);
    // 2. 关键：立即在图片后插入一个换行符，并把光标移过去
    _quillC.replaceText(index + 1, 0, '\n', null);
    _quillC.updateSelection(
      TextSelection.collapsed(offset: index + 2),
      quill.ChangeSource.local,
    );
  }

  // 弹出 GIF 选择器
  void _pickGif() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7, // 初始高度 70%
          minChildSize: 0.4, // 最小高度
          maxChildSize: 0.95, // 最大高度
          expand: false, // 设为 false 以便由 Container 控制顶部圆角
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 20,
                    offset: Offset(0, -5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                child: _GifSearchSheet(
                  scrollController: scrollController,
                  onGifSelected: (url) {
                    Navigator.pop(context);
                    _insertImageToEditor(url);
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _toggleAttribute(quill.Attribute attribute) {
    final style = _quillC.getSelectionStyle();
    final currentAttr = style.attributes[attribute.key];

    if (currentAttr != null && currentAttr.value == attribute.value) {
      _quillC.formatSelection(quill.Attribute.clone(attribute, null));
    } else {
      // 应用属性
      _quillC.formatSelection(attribute);
    }
  }

  String extractPureText(quill.Document document) {
    final buffer = StringBuffer();
    for (final op in document.toDelta().toList()) {
      if (op.isInsert && op.data is String) {
        buffer.write(op.data);
      }
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'\n+'), '\n') // 可选：压缩多余换行
        .trim();
  }

  Future<void> _submit() async {
    if (_titleC.text.trim().isEmpty) {
      AppToast.show(context, message: '请填写标题');
      return;
    }

    setState(() => _isSubmitting = true);
    final DbService db = Get.find();
    final StorageService storage = Get.find();

    final delta = _quillC.document.toDelta();
    final jsonContent = jsonEncode(delta.toJson());
    final plainText = extractPureText(_quillC.document);

    String? firstImage;
    for (var op in delta.toList()) {
      if (op.isInsert && op.data is Map) {
        final map = op.data as Map;
        if (map.containsKey('image')) {
          firstImage = map['image'].toString();
          break;
        }
      }
    }

    final uid = storage.getUserId();
    if (uid != null) {
      await db.createPost(
        uid,
        _titleC.text.trim(),
        jsonContent,
        plainText,
        firstImage,
      );
      if (mounted) {
        AppToast.show(context, message: '文章发布成功', type: ToastType.success);
        Get.back(result: true);
      }
    }
    if (mounted) setState(() => _isSubmitting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          '记录灵感',
          style: TextStyle(color: Color(0xFF2C3E50), fontSize: 17),
        ),
        leading: IconButton(
          icon: const HugeIcon(
            icon: HugeIcons.strokeRoundedCancel02,
            size: 30.0,
            color: Colors.black54,
          ),
          onPressed: () => Get.back(),
        ),
        actions: [_buildPublishBtn()],
      ),
      body: Column(
        children: [
          _TitleInput(controller: _titleC),
          // 悬浮工具栏
          _EnhancedToolbar(
            controller: _quillC,
            onImageTap: _pickImage,
            onGifTap: _pickGif,
            onToggle: _toggleAttribute,
          ),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: quill.QuillEditor(
                controller: _quillC,
                scrollController: _editorScrollC,
                focusNode: FocusNode(),
                config: quill.QuillEditorConfig(
                  placeholder: '这一刻的想法...',
                  autoFocus: false,
                  checkBoxReadOnly: false,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  expands: true,
                  embedBuilders: FlutterQuillEmbeds.editorBuilders(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublishBtn() {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton(
        onPressed: _isSubmitting ? null : _submit,
        child: _isSubmitting
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.blueAccent,
                ),
              )
            : const Text(
                '发布',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Color(0xFF4A6CF7),
                ),
              ),
      ),
    );
  }
}

class _TitleInput extends StatelessWidget {
  final TextEditingController controller;
  const _TitleInput({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: TextField(
        controller: controller,
        style: const TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937),
        ),
        decoration: const InputDecoration(
          hintText: '标题...',
          hintStyle: TextStyle(color: Color(0xFFD1D5DB)),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

/// =====================
/// GIF 搜索和展示面板 (内部组件 - 美化版)
/// =====================
class _GifSearchSheet extends StatefulWidget {
  final ScrollController scrollController;
  final Function(String url) onGifSelected;

  const _GifSearchSheet({
    required this.scrollController,
    required this.onGifSelected,
  });

  @override
  State<_GifSearchSheet> createState() => _GifSearchSheetState();
}

class _GifSearchSheetState extends State<_GifSearchSheet> {
  final TextEditingController _searchC = TextEditingController();
  List<String> _gifs = [];
  bool _isLoading = false;
  final FocusNode _searchFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 初始加载空关键词 (通常返回热门GIF)
    _fetchGifs('');
  }

  @override
  void dispose() {
    _searchC.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _fetchGifs(String query) async {
    _searchFocus.unfocus();

    setState(() => _isLoading = true);
    final gifs = await ApiService.fetchIntercomGifs(query: query);
    if (mounted) {
      setState(() {
        _gifs = gifs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          color: Colors.white,
          child: Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),

        // 2. 搜索框区域
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: TextField(
            controller: _searchC,
            focusNode: _searchFocus,
            textInputAction: TextInputAction.search,
            cursorColor: Colors.blueAccent,
            style: const TextStyle(fontSize: 15, color: Color(0xFF2C3E50)),
            onSubmitted: (value) => _fetchGifs(value),
            decoration: InputDecoration(
              hintText: '搜索有趣的 GIF...',
              hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
              prefixIcon: HugeIcon(
                icon: HugeIcons.strokeRoundedSearch02,
                size: 10,
                color: Colors.grey[300],
              ),
              filled: true,
              fillColor: const Color(0xFFF5F7FA), // 很浅的灰蓝色背景
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: 16,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16), // 更圆润的边角
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Colors.blueAccent,
                  width: 1,
                ),
              ),
              suffixIcon: IconButton(
                icon: HugeIcon(
                  icon: HugeIcons.strokeRoundedArrowRight01,
                  color: Colors.blueAccent,
                  size: 22,
                ),
                onPressed: () => _fetchGifs(_searchC.text),
              ),
            ),
          ),
        ),

        // 3. 内容展示区域
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.blueAccent, // 指定的加载颜色
                  ),
                )
              : _gifs.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HugeIcon(
                        icon: HugeIcons.strokeRoundedSearch02,
                        size: 48,
                        color: Colors.grey[300],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '没有找到相关 GIF',
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                    ],
                  ),
                )
              : GridView.builder(
                  // 关键：将外部传入的 controller 给 GridView，实现拖拽联动
                  controller: widget.scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12, // 增加间距
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.0, // 1:1 正方形展示，看起来更整齐
                  ),
                  itemCount: _gifs.length,
                  itemBuilder: (context, index) {
                    final url = _gifs[index];
                    return Material(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => widget.onGifSelected(url),
                        splashColor: Colors.blueAccent.withOpacity(0.1),
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          // 加载过程优化
                          loadingBuilder: (ctx, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  value:
                                      loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                      : null,
                                  color: Colors.blueAccent.withOpacity(0.5),
                                ),
                              ),
                            );
                          },
                          // 错误处理优化
                          errorBuilder: (ctx, err, stack) => Center(
                            child: Icon(
                              Icons.broken_image_rounded,
                              color: Colors.grey[300],
                              size: 30,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// =====================
/// 增强版工具栏：已修复状态同步问题
/// =====================
class _EnhancedToolbar extends StatelessWidget {
  final quill.QuillController controller;
  final VoidCallback onImageTap;
  final VoidCallback onGifTap;
  final Function(quill.Attribute) onToggle;

  const _EnhancedToolbar({
    required this.controller,
    required this.onImageTap,
    required this.onGifTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      // 【修复 2】使用 ListenableBuilder 监听 controller
      // 相比 StreamBuilder(controller.changes)，它能更敏锐地捕捉光标移动和格式变化
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          return ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              // 图片插入
              _toolBtn(
                HugeIcons.strokeRoundedImage01,
                null,
                isAction: true,
                onTap: onImageTap,
              ),
              // GIF 插入按钮
              _toolBtn(
                HugeIcons.strokeRoundedGif01,
                null,
                isAction: true,
                onTap: onGifTap,
              ),

              _vDivider(),

              // 基础文本格式
              _toolBtn(HugeIcons.strokeRoundedTextBold, quill.Attribute.bold),
              _toolBtn(
                HugeIcons.strokeRoundedTextItalic,
                quill.Attribute.italic,
              ),
              _toolBtn(
                HugeIcons.strokeRoundedTextUnderline,
                quill.Attribute.underline,
              ),
              _vDivider(),

              // 标题与引用
              _toolBtn(HugeIcons.strokeRoundedHeading01, quill.Attribute.h1),
              _toolBtn(HugeIcons.strokeRoundedHeading02, quill.Attribute.h2),
              _toolBtn(
                HugeIcons.strokeRoundedQuoteUp,
                quill.Attribute.blockQuote,
              ),
              _vDivider(),

              // 列表
              _toolBtn(
                HugeIcons.strokeRoundedLeftToRightListBullet,
                quill.Attribute.ul,
              ),
              _toolBtn(
                HugeIcons.strokeRoundedLeftToRightListNumber,
                quill.Attribute.ol,
              ),
              // 对齐
              _toolBtn(
                HugeIcons.strokeRoundedTextAlignCenter,
                quill.Attribute.centerAlignment,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _vDivider() => const VerticalDivider(
    indent: 14,
    endIndent: 14,
    width: 24,
    color: Color(0xFFF0F0F0),
  );

  Widget _toolBtn(
    dynamic icon, // HugeIcons 通常是 dynamic 或 List<dynamic>
    quill.Attribute? attr, {
    bool isAction = false,
    VoidCallback? onTap,
  }) {
    // 【修复 3】严格比对属性值
    // 不再只用 containsKey，而是检查 value 是否相等
    // 例如：H1 和 H2 都是 'header' key，必须比对 value 1 或 2 才能区分高亮
    bool isActive = false;
    if (attr != null && !isAction) {
      final style = controller.getSelectionStyle();
      final currentAttr = style.attributes[attr.key];
      if (currentAttr != null) {
        isActive = currentAttr.value == attr.value;
      }
    }

    return IconButton(
      icon: HugeIcon(
        icon: icon,
        color: isActive ? const Color(0xFF4A6CF7) : const Color(0xFF6B7280),
        size: 22,
      ),
      onPressed: isAction ? onTap : () => onToggle(attr!),
      splashRadius: 24,
    );
  }
}
