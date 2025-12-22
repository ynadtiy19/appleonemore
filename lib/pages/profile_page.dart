import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../controllers/auth_controller.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import '../services/db_service.dart';
import 'edit_profile_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final AuthController authC = Get.find();

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text('我的主页', style: TextStyle(color: Colors.black87)),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedLogoutSquare01,
              size: 20.0,
            ),
            onPressed: authC.logout,
            tooltip: '退出登录',
          ),
        ],
      ),
      body: Obx(() {
        final User? user = authC.currentUser.value;
        if (user == null) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.blueAccent),
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _HeaderCard(user: user),
              const SizedBox(height: 16),
              _StatCard(user: user),
              const SizedBox(height: 16),
              _BioCard(user: user),
              const SizedBox(height: 24),
              _EditButton(),
              const SizedBox(height: 30),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "我的动态",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              // 🔥 新增：我的帖子列表
              _MyPostsList(userId: user.id),
            ],
          ),
        );
      }),
    );
  }
}

class _MyPostsList extends StatefulWidget {
  final int userId;
  const _MyPostsList({required this.userId});

  @override
  State<_MyPostsList> createState() => _MyPostsListState();
}

class _MyPostsListState extends State<_MyPostsList> {
  final DbService _db = Get.find();
  List<Post> _myPosts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMyPosts();
  }

  Future<void> _loadMyPosts() async {
    try {
      final posts = await _db.getUserPosts(widget.userId);
      if (mounted) {
        setState(() {
          _myPosts = posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deletePost(int postId) async {
    bool? confirm = await Get.dialog(
      AlertDialog(
        title: const Text("确认删除"),
        content: const Text("删除后无法恢复，确定要继续吗？"),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Get.back(result: true),
            child: const Text("删除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _db.deletePost(postId);
      _loadMyPosts(); // 刷新列表
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("已删除"),
          behavior: SnackBarBehavior.floating, // 悬浮式 SnackBar 更美观
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.blueAccent),
      );
    }
    if (_myPosts.isEmpty) {
      return const Text("暂无动态", style: TextStyle(color: Colors.grey));
    }

    return VisibilityDetector(
      key: const Key('MyPostsList_visibility'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction == 1.0) {
          _loadMyPosts();
        }
      },
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(), // 让外层滚动
        shrinkWrap: true,
        itemCount: _myPosts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final post = _myPosts[index];
          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              title: Text(
                post.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                DateFormat('yyyy-MM-dd HH:mm').format(post.createdAt),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.grey),
                // 🔥 只有这里显示删除
                onPressed: () => _deletePost(post.id),
              ),
              onTap: () async {
                // 点击跳转详情页
                // 这里需要引用 PostDetailPage，注意循环引用问题，建议提取路由
              },
            ),
          );
        },
      ),
    );
  }
}

// ... 保持 _HeaderCard, _StatCard, _BioCard, _EditButton 不变 ...
class _HeaderCard extends StatelessWidget {
  final User user;

  const _HeaderCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: Colors.grey.shade200,
            backgroundImage:
                (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                ? NetworkImage(user.avatarUrl!)
                : null,
            child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                ? const Icon(Icons.person, size: 44, color: Colors.grey)
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            user.nickname ?? '未设置昵称',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text('@${user.username}', style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final User user;

  const _StatCard({required this.user});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _statItem('关注', user.followingCount),
          _divider(),
          _statItem('粉丝', user.followersCount),
          _divider(),
          _statItem('获赞', 0),
        ],
      ),
    );
  }

  Widget _statItem(String label, int count) {
    return Column(
      children: [
        Text(
          count.toString(),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.grey)),
      ],
    );
  }

  Widget _divider() {
    return Container(width: 1, height: 24, color: Colors.grey.shade200);
  }
}

class _BioCard extends StatelessWidget {
  final User user;

  const _BioCard({required this.user});

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '简介',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            (user.bio != null && user.bio!.isNotEmpty)
                ? user.bio!
                : '这个人很懒，什么都没写。',
            style: const TextStyle(height: 1.6, color: Colors.black87),
          ),
          if (user.externalLink != null && user.externalLink!.isNotEmpty) ...[
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _openLink(user.externalLink!),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 16, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      user.externalLink!,
                      style: const TextStyle(
                        color: Colors.blueGrey,
                        decoration: TextDecoration.underline,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EditButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => Get.to(() => const EditProfilePage()),
        icon: const Icon(Icons.edit),
        label: const Text('编辑资料'),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.grey.shade900,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
