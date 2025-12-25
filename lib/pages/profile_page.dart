import 'package:appleonemore/pages/post_detail_page.dart';
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
      backgroundColor: const Color(0xFFF2F4F7),
      body: Obx(() {
        final User? user = authC.currentUser.value;
        if (user == null) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.black87),
          );
        }

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              // 🔥 修复：增加展开高度，从 380 改为 420 (或者根据实际内容调整)
              // 之前的 380 减去 top padding 100 只剩 280，不足以放下所有内容
              expandedHeight: 420.0,
              floating: false,
              pinned: true,
              backgroundColor: Colors.white,
              elevation: 0,
              centerTitle: true,
              title: Text(
                user.nickname ?? '个人主页',
                style: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              actions: [
                IconButton(
                  icon: const HugeIcon(
                    icon: HugeIcons.strokeRoundedLogoutCircle02,
                    size: 24.0,
                    color: Colors.black87,
                  ),
                  onPressed: () => _showLogoutDialog(context, authC),
                  tooltip: '退出登录',
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  color: Colors.white,
                  // 🔥 修复：稍微减少顶部 padding，给内容留出更多空间
                  // 之前是 top: 100，改为 top: 80
                  padding: const EdgeInsets.only(
                    top: 80,
                    left: 20,
                    right: 20,
                    bottom: 20,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _ProfileHeader(user: user),
                      // 🔥 修复：稍微减少间距
                      const SizedBox(height: 16),
                      _StatsRow(user: user),
                      const SizedBox(height: 16),
                      _ActionButtons(user: user),
                    ],
                  ),
                ),
              ),
            ),

            if ((user.bio != null && user.bio!.isNotEmpty) ||
                (user.externalLink != null && user.externalLink!.isNotEmpty))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: _BioSection(user: user),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "我的动态",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            _MyPostsSliverList(userId: user.id),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        );
      }),
    );
  }

  void _showLogoutDialog(BuildContext context, AuthController authC) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('确定要退出当前账号吗？'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              authC.logout();
            },
            child: const Text('退出', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// 组件：顶部头像与名称
// =============================================================================
class _ProfileHeader extends StatelessWidget {
  final User user;
  const _ProfileHeader({required this.user});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 头像
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.grey.shade200, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 40,
            backgroundColor: Colors.grey.shade100,
            backgroundImage:
                (user.avatarUrl != null && user.avatarUrl!.isNotEmpty)
                ? NetworkImage(user.avatarUrl!)
                : null,
            child: (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                ? Icon(Icons.person, size: 40, color: Colors.grey.shade400)
                : null,
          ),
        ),
        const SizedBox(height: 12),
        // 昵称
        Text(
          user.nickname ?? '未设置昵称',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.black87,
            letterSpacing: 0.5,
          ),
        ),
        // 用户名
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '@${user.username}',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// 组件：数据统计行
// =============================================================================
class _StatsRow extends StatelessWidget {
  final User user;
  const _StatsRow({required this.user});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildStatItem('关注', user.followingCount),
          _buildDivider(),
          _buildStatItem('粉丝', user.followersCount),
          _buildDivider(),
          _buildStatItem('获赞', 0), // 假设User模型暂无此字段，设为0
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {}, // 可以在此添加点击跳转到粉丝列表等
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Column(
            children: [
              Text(
                _formatCount(count),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return VerticalDivider(
      color: Colors.grey.shade300,
      thickness: 1,
      width: 1,
      indent: 8,
      endIndent: 8,
    );
  }

  String _formatCount(int count) {
    if (count > 10000) {
      return '${(count / 10000).toStringAsFixed(1)}w';
    }
    return count.toString();
  }
}

// =============================================================================
// 组件：操作按钮 (编辑资料)
// =============================================================================
class _ActionButtons extends StatelessWidget {
  final User user;
  const _ActionButtons({required this.user});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => EditProfilePage()),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black87,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Text(
          '编辑资料',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// =============================================================================
// 组件：简介与链接
// =============================================================================
class _BioSection extends StatelessWidget {
  final User user;
  const _BioSection({required this.user});

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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (user.bio != null && user.bio!.isNotEmpty) ...[
            const Row(
              children: [
                HugeIcon(
                  icon: HugeIcons.strokeRoundedQuoteDown,
                  size: 16,
                  color: Colors.grey,
                ),
                SizedBox(width: 8),
                Text(
                  "简介",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              user.bio!,
              style: const TextStyle(
                fontSize: 14,
                height: 1.6,
                color: Colors.black87,
              ),
            ),
          ],
          if (user.externalLink != null && user.externalLink!.isNotEmpty) ...[
            if (user.bio != null && user.bio!.isNotEmpty)
              const SizedBox(height: 16),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _openLink(user.externalLink!),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const HugeIcon(
                      icon: HugeIcons.strokeRoundedLink01,
                      size: 18,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        user.externalLink!,
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_forward_ios,
                      size: 12,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// 组件：帖子列表 (Sliver)
// =============================================================================
class _MyPostsSliverList extends StatefulWidget {
  final int userId;
  const _MyPostsSliverList({required this.userId});

  @override
  State<_MyPostsSliverList> createState() => _MyPostsSliverListState();
}

class _MyPostsSliverListState extends State<_MyPostsSliverList> {
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
        backgroundColor: Colors.white,
        title: const Text("确认删除"),
        content: const Text("删除后无法恢复，确定要继续吗？"),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text("取消", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text("删除"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _db.deletePost(postId);
      _loadMyPosts(); // 刷新列表
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text("帖子已删除"),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.black87,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 50),
          child: Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.black87,
            ),
          ),
        ),
      );
    }

    if (_myPosts.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.only(top: 40),
          alignment: Alignment.center,
          child: Column(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedNote01,
                size: 64,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 16),
              Text(
                "暂无动态",
                style: TextStyle(color: Colors.grey.shade500, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return SliverVisibilityDetector(
      key: const Key('MyPostsList_visibility'),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final post = _myPosts[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: _PostCard(post: post, onDelete: () => _deletePost(post.id)),
          );
        }, childCount: _myPosts.length),
      ),
      onVisibilityChanged: (info) {
        if (info.visibleFraction == 1.0) {
          // 可选：实现自动刷新逻辑
        }
      },
    );
  }
}

// =============================================================================
// 组件：单个帖子卡片样式
// =============================================================================
class _PostCard extends StatelessWidget {
  final Post post;
  final VoidCallback onDelete;

  const _PostCard({required this.post, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    // 判断是否有图片
    final hasImage = post.firstImage != null && post.firstImage!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => PostDetailPage(postId: post.id),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左侧内容区域
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 标题
                          Text(
                            post.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          // 摘要
                          Text(
                            post.plainText,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              height: 1.5,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // 右侧图片 (如果有)
                    if (hasImage) ...[
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          post.firstImage!,
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                width: 70,
                                height: 70,
                                color: Colors.grey.shade200,
                                child: const Icon(
                                  Icons.image_not_supported,
                                  color: Colors.grey,
                                ),
                              ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1, color: Color(0xFFF5F5F5)),
                const SizedBox(height: 10),
                // 底部信息栏
                Row(
                  children: [
                    // 时间
                    Icon(
                      Icons.access_time,
                      size: 14,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('MM-dd HH:mm').format(post.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const Spacer(),
                    // 点赞数
                    _buildIconLabel(
                      HugeIcons.strokeRoundedFavourite,
                      post.likeCount.toString(),
                    ),
                    const SizedBox(width: 16),
                    // 评论数
                    _buildIconLabel(
                      HugeIcons.strokeRoundedComment01,
                      post.commentCount.toString(),
                    ),
                    const SizedBox(width: 8),
                    // 删除按钮 (使用PopupMenu防止误触，或者直接图标)
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedDelete02,
                          size: 18,
                          color: Colors.grey,
                        ),
                        onPressed: onDelete,
                        tooltip: "删除",
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconLabel(List<List<dynamic>> icon, String label) {
    return Row(
      children: [
        HugeIcon(icon: icon, size: 16, color: Colors.grey.shade400),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
      ],
    );
  }
}
