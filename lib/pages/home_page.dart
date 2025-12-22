import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';

import '../controllers/home_controller.dart';
import '../models/post_model.dart';
import 'editor_page.dart';
import 'post_detail_page.dart';
import 'user_profile_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(HomeController());

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text(
          "观笔 动态",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: c.loadPosts,
            icon: const HugeIcon(
              icon: HugeIcons.strokeRoundedGlobalRefresh,
              size: 20.0,
            ),
          ),
        ],
      ),
      body: Obx(() {
        if (c.isLoading.value) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.blueAccent),
          );
        }
        if (c.posts.isEmpty) {
          return const Center(
            child: Text("暂无内容，快来发布第一篇吧！", style: TextStyle(color: Colors.grey)),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.only(top: 10, bottom: 80),
          itemCount: c.posts.length,
          itemBuilder: (context, index) {
            final post = c.posts[index];
            return _PostListItem(
              post: post,
              onTap: () async {
                await Get.to(() => PostDetailPage(postId: post.id));
                c.silentUpdate();
              },
              onUserTap: () {
                Get.to(
                  () => UserProfilePage(
                    userId: post.userId,
                    userName: post.authorName,
                  ),
                );
              },
              // 🔥 首页不显示删除按钮
              onDelete: null,
            );
          },
          separatorBuilder: (context, index) =>
              Container(height: 1, color: const Color(0xFFF7F7F7)),
        );
      }),
      floatingActionButton: _CustomFloatingActionButton(
        onPressed: () async {
          final result = await Get.to(() => const EditorPage());
          if (result == true) c.loadPosts();
        },
      ),
    );
  }
}

class _PostListItem extends StatelessWidget {
  final Post post;
  final VoidCallback onTap;
  final VoidCallback onUserTap;
  final VoidCallback? onDelete; // 可为空

  const _PostListItem({
    required this.post,
    required this.onTap,
    required this.onUserTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = post.firstImage != null && post.firstImage!.isNotEmpty;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  height: 1.4,
                  color: Colors.black87,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),

              GestureDetector(
                onTap: onUserTap,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 10,
                      backgroundImage: post.authorAvatar != null
                          ? NetworkImage(post.authorAvatar!)
                          : null,
                      backgroundColor: Colors.grey[200],
                      child: post.authorAvatar == null
                          ? const Icon(
                              Icons.person,
                              size: 12,
                              color: Colors.grey,
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      post.authorName ?? '匿名用户',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      DateFormat('MM-dd').format(post.createdAt),
                      style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),
              _buildContentRow(hasImage),
              const SizedBox(height: 12),
              _buildFooterRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentRow(bool hasImage) {
    final String summary = post.plainText.replaceAll('\n', ' ').trim();
    final bool hasText = summary.isNotEmpty;

    if (!hasText && !hasImage) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasText)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: hasImage ? 12.0 : 0),
              child: Text(
                summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ),
          ),

        if (hasImage)
          ClipRRect(
            borderRadius: BorderRadius.circular(8.0),
            child: Container(
              width: 110,
              height: 75,
              color: Colors.grey[100],
              child: Image.network(
                post.firstImage!,
                fit: BoxFit.cover,
                errorBuilder: (ctx, err, stack) =>
                    const Icon(Icons.broken_image, color: Colors.grey),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFooterRow() {
    return Row(
      children: [
        HugeIcon(
          icon: HugeIcons.strokeRoundedFavourite,
          size: 14,
          color: Colors.grey[500],
        ),
        const SizedBox(width: 4),
        Text(
          "${post.likeCount}",
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        const SizedBox(width: 16),
        HugeIcon(
          icon: HugeIcons.strokeRoundedComment03,
          size: 14,
          color: Colors.grey[500],
        ),
        const SizedBox(width: 4),
        Text(
          "${post.commentCount}",
          style: TextStyle(color: Colors.grey[600], fontSize: 13),
        ),
        const Spacer(),
        // 🔥 只有当 onDelete 不为空时才显示删除按钮
        if (onDelete != null)
          InkWell(
            onTap: onDelete,
            child: const Padding(
              padding: EdgeInsets.all(4.0),
              child: Icon(Icons.delete, size: 16, color: Colors.grey),
            ),
          ),
      ],
    );
  }
}

class _CustomFloatingActionButton extends StatefulWidget {
  final VoidCallback onPressed;
  const _CustomFloatingActionButton({required this.onPressed});

  @override
  State<_CustomFloatingActionButton> createState() =>
      _CustomFloatingActionButtonState();
}

class _CustomFloatingActionButtonState
    extends State<_CustomFloatingActionButton> {
  double _opacity = 1.0;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(34),
        onTapDown: (_) => setState(() => _opacity = 0.5),
        onTapUp: (_) => setState(() => _opacity = 1.0),
        onTapCancel: () => setState(() => _opacity = 1.0),
        onTap: widget.onPressed,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: AnimatedOpacity(
          opacity: _opacity,
          duration: const Duration(milliseconds: 50),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color.fromRGBO(83, 140, 255, 1),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [
                BoxShadow(
                  color: const Color.fromRGBO(83, 140, 255, 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.edit, color: Colors.white, size: 28),
          ),
        ),
      ),
    );
  }
}
