import 'dart:convert';
import 'dart:async'; // 引入异步支持

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill;
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../controllers/home_controller.dart';
import '../models/post_model.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../services/storage_service.dart';
import 'user_profile_page.dart';

class PostDetailPage extends StatefulWidget {
  final int postId;
  const PostDetailPage({super.key, required this.postId});

  @override
  State<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends State<PostDetailPage> with TickerProviderStateMixin {
  final DbService _db = Get.find();
  final StorageService _storage = Get.find();

  final _commentC = TextEditingController();
  quill.QuillController? _readC;

  Post? _post;
  bool _isLoadingPost = true;
  List<Comment> comments = [];
  bool isLiked = false;
  int likeCount = 0;

  // --- 翻译相关状态 ---
  bool isTranslating = false;
  bool isShowingTranslation = false;
  quill.Delta? _originalDelta;

  // 支持的语言列表
  final Map<String, String> _supportedLanguages = {
    "zh-CN": "简体中文",
    "en": "English",
    "ja": "日本語",
    "ko": "한국어",
    "fr": "Français",
    "de": "Deutsch",
    "es": "Español",
    "ru": "Русский",
  };

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _readC?.dispose();
    _commentC.dispose();
    super.dispose();
  }

  void _initData() async {
    final post = await _db.getPost(widget.postId);
    if (mounted) {
      setState(() {
        _post = post;
        _isLoadingPost = false;
        if (post != null) likeCount = post.likeCount;
      });
    }
    if (post != null) {
      _loadQuillContent(post);
      _loadComments();
      _checkLikeStatus();
    }
  }

  void _loadQuillContent(Post post) {
    try {
      final json = jsonDecode(post.contentJson);
      final doc = quill.Document.fromJson(json);
      _readC = quill.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
      // 保存原始 Delta 用于还原
      _originalDelta = doc.toDelta();
    } catch (_) {
      // 容错：如果是纯文本
      final doc = quill.Document()..insert(0, post.plainText);
      _readC = quill.QuillController(
        document: doc,
        selection: const TextSelection.collapsed(offset: 0),
        readOnly: true,
      );
      _originalDelta = doc.toDelta();
    }
    setState(() {});
  }

  void _loadComments() async {
    final list = await _db.getComments(widget.postId);
    if (mounted) setState(() => comments = list);
  }

  void _checkLikeStatus() async {
    final uid = _storage.getUserId();
    if (uid != null) {
      try {
        bool liked = await _db.hasUserLiked(widget.postId, uid);
        if (mounted) setState(() => isLiked = liked);
      } catch (e) {
        debugPrint("Check like error: $e");
      }
    }
  }

  void _handleLike() async {
    final uid = _storage.getUserId();
    if (uid == null) {
      Get.snackbar("提示", "请先登录");
      return;
    }
    setState(() {
      isLiked = !isLiked;
      likeCount += isLiked ? 1 : -1;
    });
    await _db.toggleLike(widget.postId, uid);
  }

  Future<bool> _onWillPop() async {
    try {
      final homeC = Get.find<HomeController>();
      homeC.silentUpdate();
    } catch (_) {}
    return true;
  }

  void _sendComment() async {
    if (_commentC.text.trim().isEmpty) return;
    final uid = _storage.getUserId();
    if (uid == null) {
      Get.snackbar("提示", "请先登录");
      return;
    }
    await _db.addComment(widget.postId, uid, _commentC.text);
    _commentC.clear();
    FocusScope.of(context).unfocus();
    _loadComments();
  }

  // ================= 翻译逻辑 (核心修复) =================

  void _handleTranslateTap() {
    if (isShowingTranslation) {
      _restoreOriginal();
    } else {
      _showCustomLanguageSelector();
    }
  }

  /// 使用原生 showModalBottomSheet 替代 Get.bottomSheet，并实现自定义动画
  void _showCustomLanguageSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent, // 透明背景以显示圆角
      isScrollControlled: true,
      builder: (context) {
        return _AnimatedLanguageSheet(
          languages: _supportedLanguages,
          onLanguageSelected: (key) {
            Navigator.pop(context); // 关闭弹窗
            _performTranslate(key); // 执行翻译
          },
        );
      },
    );
  }

  /// 执行翻译并智能重组 Delta 以保留图片
  void _performTranslate(String targetLang) async {
    if (_post == null || _readC == null || _originalDelta == null) return;

    setState(() => isTranslating = true);

    try {
      // 1. 提取原文中的纯文本段落，记录结构
      // 使用分隔符来区分段落，避免翻译API合并文本导致结构丢失
      // 分隔符选用一个生僻字符串，防止与正文冲突
      const String separator = "\n|||\n";

      List<quill.Operation> originalOps = _originalDelta!.toList();
      List<String> textSegments = [];
      List<int> textIndices = []; // 记录哪些 op 是文本

      for (int i = 0; i < originalOps.length; i++) {
        final op = originalOps[i];
        if (op.data is String) {
          String text = op.data as String;
          // 忽略纯粹的换行符，除非它是唯一的结构
          if (text.trim().isNotEmpty || text == '\n') {
            textSegments.add(text);
            textIndices.add(i);
          }
        }
      }

      // 如果没有文字，直接返回
      if (textSegments.isEmpty) {
        throw Exception("没有可翻译的文本");
      }

      // 2. 拼接文本发送给 API
      String textToTranslate = textSegments.join(separator);
      final result = await ApiService.translate(textToTranslate, targetLang);

      if (result == null || result.text.isEmpty) {
        throw Exception("翻译返回为空");
      }

      // 3. 将翻译结果拆回段落
      // 注意：部分翻译API可能会吃掉分隔符或者修改它，这里需要做容错
      // 这里假设 ApiService 返回的是包含分隔符的字符串
      List<String> translatedSegments = result.text.split(separator.trim());

      // 如果拆分后的数量不对，尝试用另一种方式拆分或者直接作为全文
      // 容错策略：如果结构完全乱了，就回退到 "译文全文 + 底部所有图片" 的模式
      bool structureBroken = translatedSegments.length != textSegments.length;

      quill.Delta newDelta = quill.Delta();

      if (!structureBroken) {
        // --- 方案 A: 完美还原模式 ---
        int textCounter = 0;
        for (int i = 0; i < originalOps.length; i++) {
          final op = originalOps[i];
          if (op.data is String) {
            // 是文本，替换为译文
            // 只有当我们在提取时记录了这个op，才进行替换
            if (textCounter < translatedSegments.length &&
                (op.data as String).trim().isNotEmpty) {
              newDelta.insert(translatedSegments[textCounter], op.attributes);
              textCounter++;
            } else {
              // 保留原来的换行符等微小结构
              newDelta.insert(op.data, op.attributes);
            }
          } else {
            // 是图片/视频，原样保留！
            newDelta.insert(op.data, op.attributes);
          }
        }
      } else {
        // --- 方案 B: 容错模式 (译文 + 图片追加在底部) ---
        // 插入全部译文
        newDelta.insert(result.text.replaceAll("|||", "\n"));
        newDelta.insert("\n\n");

        // 遍历提取所有图片，追加在后面
        for (var op in originalOps) {
          if (op.data is! String) {
            newDelta.insert(op.data, op.attributes);
            newDelta.insert("\n");
          }
        }
      }

      // 4. 更新控制器
      setState(() {
        _readC = quill.QuillController(
          document: quill.Document.fromDelta(newDelta),
          selection: const TextSelection.collapsed(offset: 0),
          readOnly: true,
        );
        isShowingTranslation = true;
      });

      Get.snackbar(
        "翻译成功",
        "已切换至 ${_supportedLanguages[targetLang]}",
        backgroundColor: Colors.green.withOpacity(0.1),
        colorText: Colors.green[800],
      );

    } catch (e) {
      Get.snackbar("翻译失败", e.toString());
      print("Translation Error: $e");
    } finally {
      if (mounted) setState(() => isTranslating = false);
    }
  }

  void _restoreOriginal() {
    if (_originalDelta != null) {
      setState(() {
        _readC = quill.QuillController(
          document: quill.Document.fromDelta(_originalDelta!),
          selection: const TextSelection.collapsed(offset: 0),
          readOnly: true,
        );
        isShowingTranslation = false;
      });
    }
  }

  void _goToAuthorProfile() {
    if (_post == null) return;
    Get.to(
          () => UserProfilePage(userId: _post!.userId, userName: _post!.authorName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: const Color(0xFFF7F8FA),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () {
              _onWillPop();
              Get.back();
            },
          ),
          centerTitle: true,
          title: _isLoadingPost
              ? const SizedBox()
              : GestureDetector(
            onTap: _goToAuthorProfile,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundImage: (_post?.authorAvatar != null)
                      ? NetworkImage(_post!.authorAvatar!)
                      : null,
                  child: _post?.authorAvatar == null
                      ? const Icon(Icons.person, size: 16)
                      : null,
                ),
                const SizedBox(width: 8),
                Text(
                  _post?.authorName ?? "Unknown",
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                ),
              ],
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _buildTranslateButton(),
            ),
          ],
        ),
        body: _isLoadingPost
            ? const Center(
          child: CircularProgressIndicator(color: Colors.blueAccent),
        )
            : _post == null
            ? const Center(child: Text("文章不存在或已被删除"))
            : Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
                    Text(
                      _post!.title,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 信息栏
                    Row(
                      children: [
                        Text(
                          DateFormat('yyyy年MM月dd日 HH:mm').format(_post!.createdAt),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 13,
                          ),
                        ),
                        if (isShowingTranslation) ...[
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blue.withOpacity(0.2)),
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.translate, size: 12, color: Colors.blue),
                                SizedBox(width: 4),
                                Text(
                                  "机器译文",
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Quill 内容区域
                    if (_readC != null)
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 300),
                        opacity: isTranslating ? 0.3 : 1.0,
                        child: quill.QuillEditor.basic(
                          controller: _readC!,
                          config: quill.QuillEditorConfig(
                            embedBuilders: FlutterQuillEmbeds.editorBuilders(),
                          ),
                        ),
                      ),

                    const SizedBox(height: 40),
                    _buildLikeBar(),
                    const Divider(height: 40),
                    const Text(
                      "精选评论",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (comments.isEmpty)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            "暂无评论",
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      ),
                    ...comments.map((c) => _buildCommentItem(c)),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            _buildBottomInput(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildTranslateButton() {
    if (isTranslating) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
      );
    }
    return IconButton(
      onPressed: _handleTranslateTap,
      tooltip: isShowingTranslation ? "还原原文" : "翻译文章",
      icon: isShowingTranslation
          ? const Icon(Icons.g_translate, color: Colors.blue)
          : const Icon(Icons.translate_rounded, color: Colors.black54),
    );
  }

  Widget _buildLikeBar() {
    return Row(
      children: [
        InkWell(
          onTap: _handleLike,
          borderRadius: BorderRadius.circular(30),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isLiked ? Colors.pink.shade50 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(
                color: isLiked ? Colors.pink.shade100 : Colors.transparent,
              ),
              boxShadow: isLiked
                  ? [BoxShadow(color: Colors.pink.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 4))]
                  : [],
            ),
            child: Row(
              children: [
                HugeIcon(
                  icon: isLiked ? HugeIcons.strokeRoundedFavourite : HugeIcons.strokeRoundedFavourite,
                  size: 24,
                  color: isLiked ? Colors.pink : Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  "$likeCount",
                  style: TextStyle(
                    color: isLiked ? Colors.pink : Colors.grey[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Text(
          "${comments.length} 条评论",
          style: TextStyle(color: Colors.grey[500], fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildCommentItem(Comment c) {
    return InkWell(
      onTap: () {
        Get.to(() => UserProfilePage(userId: c.userId, userName: c.authorName));
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.blue.shade50,
              backgroundImage: (c.authorAvatar != null)
                  ? NetworkImage(c.authorAvatar!)
                  : null,
              child: c.authorAvatar == null
                  ? Text(
                c.authorName.isNotEmpty ? c.authorName[0].toUpperCase() : "?",
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.bold,
                ),
              )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        c.authorName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        DateFormat('MM-dd HH:mm').format(c.createdAt),
                        style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c.content,
                    style: TextStyle(color: Colors.grey[800], height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomInput(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _commentC,
                  decoration: const InputDecoration(
                    hintText: "写下你的想法...",
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filled(
              onPressed: _sendComment,
              icon: const Icon(Icons.arrow_upward_rounded),
              style: IconButton.styleFrom(
                backgroundColor: theme.primaryColor,
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= 自定义动画的底部弹窗组件 =================

class _AnimatedLanguageSheet extends StatefulWidget {
  final Map<String, String> languages;
  final Function(String) onLanguageSelected;

  const _AnimatedLanguageSheet({
    required this.languages,
    required this.onLanguageSelected,
  });

  @override
  State<_AnimatedLanguageSheet> createState() => _AnimatedLanguageSheetState();
}

class _AnimatedLanguageSheetState extends State<_AnimatedLanguageSheet> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.only(top: 20, bottom: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 顶部指示条
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 标题
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedLanguageSkill,
                  color: Colors.black87,
                ),
                SizedBox(width: 10),
                Text(
                  "选择目标语言",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),

          // 动态列表
          SizedBox(
            height: 350,
            child: ListView.builder(
              itemCount: widget.languages.length,
              padding: const EdgeInsets.symmetric(vertical: 10),
              itemBuilder: (context, index) {
                final key = widget.languages.keys.elementAt(index);
                final name = widget.languages.values.elementAt(index);

                // 逐个动画效果
                final animation = Tween<Offset>(
                  begin: const Offset(0, 0.5),
                  end: Offset.zero,
                ).animate(
                  CurvedAnimation(
                    parent: _controller,
                    curve: Interval(
                      index * 0.05,
                      0.5 + index * 0.05,
                      curve: Curves.easeOutBack,
                    ),
                  ),
                );

                final fadeAnim = Tween<double>(begin: 0, end: 1).animate(
                    CurvedAnimation(
                      parent: _controller,
                      curve: Interval(index * 0.05, 0.5 + index * 0.05),
                    )
                );

                return AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    return FadeTransition(
                      opacity: fadeAnim,
                      child: SlideTransition(
                        position: animation,
                        child: InkWell(
                          onTap: () => widget.onLanguageSelected(key),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.grey[100],
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    name[0],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const Spacer(),
                                Icon(
                                  Icons.arrow_forward_ios_rounded,
                                  size: 16,
                                  color: Colors.grey[300],
                                ),
                              ],
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
        ],
      ),
    );
  }
}