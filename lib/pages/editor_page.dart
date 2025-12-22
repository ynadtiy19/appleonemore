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

  // 优化图片插入逻辑：解决光标卡死问题
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
    } else {
      if (!mounted) return;
      AppToast.show(context, message: '图片上传失败', type: ToastType.error);
    }
  }

  // 【修复 1】更精准的属性切换逻辑
  void _toggleAttribute(quill.Attribute attribute) {
    final style = _quillC.getSelectionStyle();
    final currentAttr = style.attributes[attribute.key];

    // 如果当前选区已经有这个属性，并且值也完全相同（解决 H1/H2 冲突问题）
    if (currentAttr != null && currentAttr.value == attribute.value) {
      // 移除属性：将该 Key 的值设为 null
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
/// 增强版工具栏：已修复状态同步问题
/// =====================
class _EnhancedToolbar extends StatelessWidget {
  final quill.QuillController controller;
  final VoidCallback onImageTap;
  final Function(quill.Attribute) onToggle;

  const _EnhancedToolbar({
    super.key,
    required this.controller,
    required this.onImageTap,
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
              _toolBtn(HugeIcons.strokeRoundedImage01, null, isImage: true),
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
    bool isImage = false,
  }) {
    // 【修复 3】严格比对属性值
    // 不再只用 containsKey，而是检查 value 是否相等
    // 例如：H1 和 H2 都是 'header' key，必须比对 value 1 或 2 才能区分高亮
    bool isActive = false;
    if (attr != null) {
      final style = controller.getSelectionStyle();
      final currentAttr = style.attributes[attr.key];
      if (currentAttr != null) {
        isActive = currentAttr.value == attr.value;
      }
    }

    return IconButton(
      icon: HugeIcon(
        icon: icon,
        // 激活色使用蓝色，未激活使用灰色
        color: isActive ? const Color(0xFF4A6CF7) : const Color(0xFF6B7280),
        size: 22,
      ),
      onPressed: isImage ? onImageTap : () => onToggle(attr!),
      splashRadius: 24,
    );
  }
}
