import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/auth_controller.dart';
import '../models/post_model.dart';
import '../models/user_model.dart';
import '../services/db_service.dart';
import '../services/frontend_chat_service.dart';
import 'edit_profile_page.dart';
import 'post_detail_page.dart';

class UserProfilePage extends StatefulWidget {
  final int userId;
  final String? userName;

  const UserProfilePage({super.key, required this.userId, this.userName});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final DbService _db = Get.find();
  User? _user;
  List<Post> _posts = [];
  bool _isLoading = true;
  bool _isFollowing = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = await _db.getUserById(widget.userId);
      final posts = await _db.getUserPosts(widget.userId);

      final AuthController authC = Get.find();
      final myId = authC.currentUser.value?.id;

      bool isFollowing = false;
      if (myId != null && myId != widget.userId) {
        isFollowing = await _db.checkFollowStatus(myId, widget.userId);
      }

      if (mounted) {
        setState(() {
          _user = user;
          _posts = posts;
          _isFollowing = isFollowing; // 更新状态
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleFollow() async {
    // 1. 获取当前用户
    final AuthController authC = Get.find();
    final FrontendChatService chatService = Get.find();
    final myId = authC.currentUser.value?.id;

    if (myId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("请先登录")));
      return;
    }

    if (myId == widget.userId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("不能关注自己")));
      return;
    }

    try {
      setState(() {
        _isFollowing = !_isFollowing;
      });

      final newStatus = await _db.toggleFollow(myId, widget.userId);

      if (newStatus == true) {
        chatService.sendFollowNotification(targetUserId: widget.userId);
      }

      if (mounted) {
        if (newStatus != _isFollowing) {
          setState(() => _isFollowing = newStatus);
        }

        final msg = newStatus ? "已关注" : "已取消关注";
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            duration: const Duration(milliseconds: 1000),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isFollowing = !_isFollowing);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("操作失败，请重试")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            widget.userName ?? "加载中...",
            style: const TextStyle(color: Colors.black),
          ),
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          actions: [],
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.indigoAccent),
        ),
      );
    }

    if (_user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        appBar: AppBar(
          title: const Text("用户不存在", style: TextStyle(color: Colors.black)),
          backgroundColor: Colors.white,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          actions: [],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const HugeIcon(
                icon: HugeIcons.strokeRoundedUserBlock01,
                size: 64,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text("无法找到该用户", style: TextStyle(color: Colors.grey.shade600)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA), // 浅灰蓝背景
      body: CustomScrollView(
        slivers: [
          // 1. 顶部导航栏 (随着滚动显示名字)
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0.5,
            leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                size: 20,
                color: Colors.black87,
              ),
              onPressed: () => Get.back(),
            ),
            centerTitle: true,
            title: Text(
              _user!.nickname ?? _user!.username,
              style: const TextStyle(
                color: Colors.black87,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            actions: [
              // IconButton(
              //   icon: const HugeIcon(
              //     icon: HugeIcons.strokeRoundedMoreHorizontal,
              //     size: 24,
              //     color: Colors.black87,
              //   ),
              //   onPressed: () {
              //     // 更多操作：举报、拉黑等
              //   },
              // ),
            ],
          ),

          // 2. 用户信息卡片区
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                children: [
                  _buildProfileCard(),
                  const SizedBox(height: 24),
                  // "文章" 标题栏
                  Row(
                    children: [
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedDocumentCode,
                        size: 20,
                        color: Colors.indigoAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "发布的文章 (${_posts.length})",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),

          // 3. 文章列表
          _buildPostSliverList(),

          // 底部留白
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // 构建用户信息卡片
  Widget _buildProfileCard() {
    final AuthController authC = Get.find();
    final myId = authC.currentUser.value?.id;
    final isMe = (myId != null && myId == widget.userId);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // 头像
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.indigoAccent.withOpacity(0.2),
                width: 1,
              ),
            ),
            child: CircleAvatar(
              radius: 42,
              backgroundColor: Colors.grey.shade100,
              backgroundImage:
                  (_user!.avatarUrl != null && _user!.avatarUrl!.isNotEmpty)
                  ? NetworkImage(_user!.avatarUrl!)
                  : null,
              child: (_user!.avatarUrl == null || _user!.avatarUrl!.isEmpty)
                  ? Icon(Icons.person, size: 42, color: Colors.grey.shade400)
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          // 名字
          Text(
            _user!.nickname ?? "无名氏",
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          // 用户名
          Text(
            "@${_user!.username}",
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // 简介
          if (_user!.bio != null && _user!.bio!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _user!.bio!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black54,
                  height: 1.5,
                ),
              ),
            ),

          // 🔥 新增：社交媒体链接
          if (_user!.externalLink != null && _user!.externalLink!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: InkWell(
                onTap: () {
                  launchUrl(Uri.parse(_user!.externalLink!));
                },
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HugeIcon(
                      icon: HugeIcons.strokeRoundedLink01,
                      size: 16,
                      color: Colors.blueAccent,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        _user!.externalLink!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.blueAccent,
                          fontSize: 13,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 统计数据
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatItem("关注", _user!.followingCount),
              Container(width: 1, height: 24, color: Colors.grey.shade200),
              _buildStatItem("粉丝", _user!.followersCount),
              Container(width: 1, height: 24, color: Colors.grey.shade200),
              _buildStatItem("获赞", 0),
            ],
          ),
          const SizedBox(height: 24),

          // 🔥 按钮区域：如果是自己，显示编辑/分享；如果是别人，显示关注/私信
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: isMe
                        ? () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => EditProfilePage(),
                              ),
                            );
                          }
                        : _toggleFollow,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: (isMe || _isFollowing)
                          ? Colors.grey.shade200
                          : Colors.black87,
                      foregroundColor: (isMe || _isFollowing)
                          ? Colors.black87
                          : Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isMe ? "编辑资料" : (_isFollowing ? "已关注" : "关注"),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () {
                      if (isMe) {
                        // 分享主页逻辑
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("分享链接已复制")),
                        );
                      } else {
                        // 私信逻辑
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("私信功能开发中...")),
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey.shade300),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      foregroundColor: Colors.black87,
                    ),
                    child: Text(
                      isMe ? "分享主页" : "私信",
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int count) {
    return Column(
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
    );
  }

  String _formatCount(int count) {
    if (count > 10000) return "${(count / 10000).toStringAsFixed(1)}w";
    return count.toString();
  }

  // 构建文章列表 (Sliver)
  Widget _buildPostSliverList() {
    if (_posts.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.only(top: 40),
          alignment: Alignment.center,
          child: Column(
            children: [
              HugeIcon(
                icon: HugeIcons.strokeRoundedNoteEdit,
                size: 48,
                color: Colors.grey.shade300,
              ),
              const SizedBox(height: 12),
              Text("该用户暂未发布内容", style: TextStyle(color: Colors.grey.shade400)),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final post = _posts[index];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: _OtherUserPostCard(post: post),
        );
      }, childCount: _posts.length),
    );
  }
}

// 独立的帖子卡片组件
class _OtherUserPostCard extends StatelessWidget {
  final Post post;

  const _OtherUserPostCard({required this.post});

  @override
  Widget build(BuildContext context) {
    final hasImage = post.firstImage != null && post.firstImage!.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        // 只有轻微的阴影，保持干净
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700, // 略微加粗
                              color: Colors.black87,
                              height: 1.3,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            post.plainText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasImage) ...[
                      const SizedBox(width: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          post.firstImage!,
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                          errorBuilder: (ctx, err, stack) => Container(
                            width: 80,
                            height: 80,
                            color: Colors.grey.shade100,
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      DateFormat('yyyy-MM-dd').format(post.createdAt),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
                      ),
                    ),
                    const Spacer(),
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedFavourite,
                      size: 16,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "${post.likeCount}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedComment01,
                      size: 16,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "${post.commentCount}",
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
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
}
