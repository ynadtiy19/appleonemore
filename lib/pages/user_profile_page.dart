import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../models/post_model.dart';
import '../models/user_model.dart';
import '../services/db_service.dart';
import 'post_detail_page.dart';

class UserProfilePage extends StatefulWidget {
  final int userId;
  final String? userName; // 用于未加载前的占位

  const UserProfilePage({super.key, required this.userId, this.userName});

  @override
  State<UserProfilePage> createState() => _UserProfilePageState();
}

class _UserProfilePageState extends State<UserProfilePage> {
  final DbService _db = Get.find();
  User? _user;
  List<Post> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final user = await _db.getUserById(widget.userId);
      final posts = await _db.getUserPosts(widget.userId);
      if (mounted) {
        setState(() {
          _user = user;
          _posts = posts;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.userName ?? "加载中...")),
        body: const Center(
          child: CircularProgressIndicator(color: Colors.blueAccent),
        ),
      );
    }

    if (_user == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("用户不存在")),
        body: const Center(child: Text("无法找到该用户")),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: Text(_user!.nickname ?? _user!.username),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildUserInfoHeader(),
            const SizedBox(height: 10),
            _buildPostList(),
          ],
        ),
      ),
    );
  }

  Widget _buildUserInfoHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundImage:
                (_user!.avatarUrl != null && _user!.avatarUrl!.isNotEmpty)
                ? NetworkImage(_user!.avatarUrl!)
                : null,
            child: (_user!.avatarUrl == null || _user!.avatarUrl!.isEmpty)
                ? const Icon(Icons.person, size: 40, color: Colors.grey)
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            _user!.nickname ?? "无名氏",
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            "@${_user!.username}",
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Text(
            _user!.bio ?? "暂无简介",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statItem("关注", _user!.followingCount),
              Container(
                height: 20,
                width: 1,
                color: Colors.grey[300],
                margin: const EdgeInsets.symmetric(horizontal: 20),
              ),
              _statItem("粉丝", _user!.followersCount),
              Container(
                height: 20,
                width: 1,
                color: Colors.grey[300],
                margin: const EdgeInsets.symmetric(horizontal: 20),
              ),
              _statItem("文章", _posts.length),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, int count) {
    return Column(
      children: [
        Text(
          "$count",
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildPostList() {
    if (_posts.isEmpty) {
      return Container(
        height: 200,
        alignment: Alignment.center,
        child: const Text("暂无发布内容", style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(), // 让外层 SingleScrollView 滚动
      shrinkWrap: true,
      itemCount: _posts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 1),
      itemBuilder: (context, index) {
        final post = _posts[index];
        return Material(
          color: Colors.white,
          child: InkWell(
            onTap: () => Get.to(() => PostDetailPage(postId: post.id)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    post.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    post.plainText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    DateFormat('yyyy-MM-dd HH:mm').format(post.createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
