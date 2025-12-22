import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

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
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = authC.currentUser.value!;
    _nickC = TextEditingController(text: user.nickname);
    _bioC = TextEditingController(text: user.bio);
    _linkC = TextEditingController(text: user.externalLink);
    _newAvatarUrl = user.avatarUrl;
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: ImageSource.gallery);
    if (xFile == null) return;

    setState(() => _isLoading = true);

    final url = await ApiService.uploadImage(File(xFile.path));

    setState(() {
      _isLoading = false;
      if (url != null) {
        _newAvatarUrl = url;
        AppToast.show(context, message: '头像上传成功', type: ToastType.success);
      } else {
        AppToast.show(context, message: '头像上传失败', type: ToastType.error);
      }
    });
  }

  Future<void> _save() async {
    setState(() => _isLoading = true);

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
      if (mounted) setState(() => _isLoading = false);
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
            onPressed: _isLoading ? null : _save,
            child: _isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
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
          _AvatarSection(avatarUrl: _newAvatarUrl, onTap: _pickImage),
          const SizedBox(height: 24),
          _InputCard(label: '昵称', controller: _nickC),
          const SizedBox(height: 16),
          _InputCard(label: '个人简介', controller: _bioC, maxLines: 3),
          const SizedBox(height: 16),
          _InputCard(label: '外部链接', controller: _linkC, prefixIcon: Icons.link),
        ],
      ),
    );
  }
}

class _AvatarSection extends StatelessWidget {
  final String? avatarUrl;
  final VoidCallback onTap;

  const _AvatarSection({required this.avatarUrl, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: Colors.grey.shade200,
              backgroundImage: (avatarUrl != null && avatarUrl!.isNotEmpty)
                  ? NetworkImage(avatarUrl!)
                  : null,
              child: (avatarUrl == null || avatarUrl!.isEmpty)
                  ? const Icon(Icons.person, size: 42, color: Colors.grey)
                  : null,
            ),
            const SizedBox(height: 8),
            const Text(
              '点击更换头像',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final int maxLines;
  final IconData? prefixIcon;

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
          prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20) : null,
        ),
      ),
    );
  }
}
