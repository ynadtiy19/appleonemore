import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

import '../controllers/auth_controller.dart';
import '../services/api_service.dart';
import '../services/db_service.dart';
import '../widgets/app_toast.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final AuthController authC = Get.find();
  final DbService db = Get.find();

  late TextEditingController _nickC;
  late TextEditingController _bioC;
  late TextEditingController _linkC;

  String? _newAvatarUrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final user = authC.currentUser.value!;
    _nickC = TextEditingController(text: user.nickname);
    _bioC = TextEditingController(text: user.bio);
    _linkC = TextEditingController(text: user.externalLink);
    _newAvatarUrl = user.avatarUrl;
  }

  /// 保存资料逻辑
  Future<void> _save() async {
    setState(() => _isSaving = true);

    try {
      final user = authC.currentUser.value!;

      await db.updateUserInfo(
        user.id,
        _nickC.text.trim(),
        _bioC.text.trim(),
        _linkC.text.trim(),
        _newAvatarUrl ?? '',
      );

      await authC.refreshUser();

      if (mounted) {
        AppToast.show(context, message: '个人资料已更新', type: ToastType.success);
        Get.back();
      }
    } catch (e) {
      AppToast.show(context, message: '更新失败，请稍后再试', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('编辑资料'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.blueAccent,
                    ),
                  )
                : const Text(
                    '保存',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---------------------------------------------------
          // 使用圆形 UI + 编辑逻辑的组件
          // ---------------------------------------------------
          Center(
            child: AvatarFilePond(
              initialUrl: _newAvatarUrl,
              onImageUploaded: (String newUrl) {
                setState(() {
                  _newAvatarUrl = newUrl;
                });
                AppToast.show(
                  context,
                  message: '头像上传成功',
                  type: ToastType.success,
                );
              },
              onUploadFailed: () {
                AppToast.show(
                  context,
                  message: '头像上传失败',
                  type: ToastType.error,
                );
              },
            ),
          ),

          const SizedBox(height: 24),
          _InputCard(
            label: '昵称',
            controller: _nickC,
            prefixIcon: HugeIcons.strokeRoundedUser,
          ),
          const SizedBox(height: 16),
          _InputCard(
            label: '个人简介',
            controller: _bioC,
            maxLines: 3,
            prefixIcon: HugeIcons.strokeRoundedProfile02,
          ),
          const SizedBox(height: 16),
          _InputCard(
            label: '外部链接',
            controller: _linkC,
            prefixIcon: HugeIcons.strokeRoundedLink02,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. 组件封装 (_InputCard)
// ---------------------------------------------------------------------------

class _InputCard extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final List<List<dynamic>>? prefixIcon;

  const _InputCard({
    required this.label,
    required this.controller,
    this.maxLines = 1,
    this.prefixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          border: InputBorder.none,
          prefixIcon: prefixIcon != null
              ? HugeIcon(
                  icon: prefixIcon!,
                  color: Colors.grey.shade400,
                  size: 24.0,
                )
              : null,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. 整合组件: 圆形UI (Latest) + 编辑逻辑 (Logic)
// ---------------------------------------------------------------------------

class AvatarFilePond extends StatefulWidget {
  final String? initialUrl;
  final Function(String) onImageUploaded;
  final VoidCallback onUploadFailed;

  const AvatarFilePond({
    super.key,
    this.initialUrl,
    required this.onImageUploaded,
    required this.onUploadFailed,
  });

  @override
  State<AvatarFilePond> createState() => _AvatarFilePondState();
}

class _AvatarFilePondState extends State<AvatarFilePond> {
  bool _isUploading = false;
  File? _localFile;

  // 颜色定义
  final Color _backgroundColor = const Color(0xFFEDF0F4);
  final Color _textColor = const Color(0xFF4C4E53);

  // 1. 选择图片并上传
  Future<void> _handlePickAndUpload() async {
    if (_isUploading) return;

    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
    );

    if (xFile == null) return;

    final file = File(xFile.path);

    setState(() {
      _localFile = file;
    });

    await _uploadImage(file);
  }

  // 2. 编辑图片逻辑 (从原代码提取)
  Future<void> _handleEditImage() async {
    if (_localFile == null) return;

    if (mounted) {
      // 跳转到 pro_image_editor 页面
      File? editedFile = await Navigator.of(context).push<File?>(
        MaterialPageRoute(builder: (context) => ImageEditor(file: _localFile!)),
      );

      if (editedFile != null) {
        setState(() {
          _localFile = editedFile;
        });
        // 编辑完成后自动重新上传
        await _uploadImage(editedFile);
      }
    }
  }

  // 3. 上传核心逻辑
  Future<void> _uploadImage(File file) async {
    setState(() => _isUploading = true);
    try {
      final url = await ApiService.uploadImage(file);

      if (mounted) {
        if (url != null) {
          widget.onImageUploaded(url);
        } else {
          // 上传失败
          widget.onUploadFailed();
        }
      }
    } catch (e) {
      if (mounted) widget.onUploadFailed();
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 保持最新UI的尺寸: 170
    const double size = 170.0;

    return GestureDetector(
      // 点击整个圆形区域触发选择
      onTap: _handlePickAndUpload,
      child: Stack(
        children: [
          // ------------------------------------------------
          // 层级1: 虚线边框与底色 (圆形)
          // ------------------------------------------------
          CustomPaint(
            painter: DashedBorderPainter(
              color: _isUploading ? Colors.blue : const Color(0xFFBABDC0),
              strokeWidth: 2,
              dashLength: 6,
              gapLength: 4,
              borderRadius: size / 2, // 确保是圆形
            ),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: _backgroundColor,
                shape: BoxShape.circle,
              ),
              child: ClipOval(child: _buildContent()),
            ),
          ),

          // ------------------------------------------------
          // 层级2: 编辑按钮 (仿照最新UI样式)
          // 只有当有本地文件且不在上传时显示，点击触发编辑
          // ------------------------------------------------
          if (_localFile != null && !_isUploading)
            Positioned(
              bottom: 5,
              right: 0,
              left: 0,
              child: GestureDetector(
                onTap: _handleEditImage, // 点击这里触发编辑，而不是重新选择
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(8), // 稍微加大点击区域
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: HugeIcon(
                      // 使用编辑图标
                      icon: HugeIcons.strokeRoundedEdit02,
                      color: _textColor,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    // 状态 A: 正在上传
    if (_isUploading) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_localFile != null)
            Image.file(
              _localFile!,
              fit: BoxFit.cover,
              color: Colors.white.withOpacity(0.6),
              colorBlendMode: BlendMode.dstATop,
            ),
          const Center(
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Colors.blueAccent,
            ),
          ),
          Positioned(
            bottom: 35,
            left: 0,
            right: 0,
            child: Text(
              "上传中...",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: _textColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    }

    // 状态 B: 本地预览
    if (_localFile != null) {
      return Image.file(_localFile!, fit: BoxFit.cover);
    }

    // 状态 C: 网络图片
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      return Image.network(
        widget.initialUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }

    // 状态 D: 空状态
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        HugeIcon(
          icon: HugeIcons.strokeRoundedImage02,
          color: _textColor.withOpacity(0.5),
          size: 32,
        ),
        const SizedBox(height: 8),
        Text(
          "上传头像",
          textAlign: TextAlign.center,
          style: TextStyle(color: _textColor, fontSize: 12, height: 1.2),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 4. 辅助组件 (DashedPainter & ImageEditor)
// ---------------------------------------------------------------------------

class DashedBorderPainter extends CustomPainter {
  final double strokeWidth;
  final Color color;
  final double dashLength;
  final double gapLength;
  final double borderRadius;

  DashedBorderPainter({
    this.strokeWidth = 2,
    this.color = Colors.black,
    this.dashLength = 5,
    this.gapLength = 3,
    this.borderRadius = 12,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rRect = RRect.fromRectAndRadius(rect, Radius.circular(borderRadius));
    final path = Path()..addRRect(rRect);

    final Path dashedPath = Path();
    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0.0;
      while (distance < metric.length) {
        final double end = distance + dashLength;
        dashedPath.addPath(
          metric.extractPath(distance, end.clamp(0.0, metric.length)),
          Offset.zero,
        );
        distance += dashLength + gapLength;
      }
    }
    canvas.drawPath(dashedPath, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class ImageEditor extends StatelessWidget {
  const ImageEditor({super.key, required this.file});
  final File file;

  @override
  Widget build(BuildContext context) {
    return ProImageEditor.file(
      file,
      callbacks: ProImageEditorCallbacks(
        onImageEditingComplete: (bytes) async {
          // 获取临时目录保存编辑后的图片
          final tempDir = await getTemporaryDirectory();
          final newPath =
              '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}_edited.png';
          final editedFile = await File(newPath).writeAsBytes(bytes);

          if (context.mounted) Navigator.of(context).pop(editedFile);
        },
      ),
    );
  }
}
