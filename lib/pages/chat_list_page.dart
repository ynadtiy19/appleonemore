import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../controllers/chat_list_controller.dart';
import '../models/chat_session_model.dart';
import 'ChatDetailPage.dart';

class ChatListPage extends StatelessWidget {
  const ChatListPage({super.key});

  void _showUserPicker(BuildContext context, ChatListController controller) {
    controller.fetchAllUsers();
    Get.bottomSheet(
      Container(
        height: Get.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                "发起新聊天",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: Obx(
                () => ListView.builder(
                  itemCount: controller.allUsers.length,
                  itemBuilder: (context, index) {
                    final user = controller.allUsers[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage:
                            user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                            ? NetworkImage(user.avatarUrl!)
                            : null,
                        child:
                            (user.avatarUrl == null || user.avatarUrl!.isEmpty)
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(user.nickname ?? "用户_${user.id}"),
                      subtitle: Text(user.bio ?? "这一刻的想法...", maxLines: 1),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Get.back();
                        controller.startChatWithUser(user);
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(ChatListController());

    return VisibilityDetector(
      key: const Key('chat_list_page_visibility'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction == 1.0) {
          controller.loadSessions();
        }
      },
      child: Scaffold(
        backgroundColor: const Color.fromRGBO(244, 247, 254, 1),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          leading: Navigator.canPop(context)
              ? IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: Colors.black,
                    size: 20,
                  ),
                  onPressed: () => Navigator.pop(context),
                )
              : TextButton(
                  onPressed: () {},
                  child: const Text(
                    "编辑",
                    style: TextStyle(color: Color(0xFF4A6CF7), fontSize: 16),
                  ),
                ),
          title: const Text(
            "聊天",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const HugeIcon(
                icon: HugeIcons.strokeRoundedEdit02,
                color: Color(0xFF4A6CF7),
              ),
              onPressed: () => _showUserPicker(context, controller),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            Expanded(
              child: Obx(() {
                if (controller.isLoading.value) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.blueAccent),
                  );
                }

                if (controller.sessions.isEmpty) {
                  return Center(
                    child: Text(
                      "暂无聊天消息",
                      style: TextStyle(color: Colors.grey[400]),
                    ),
                  );
                }

                return RefreshIndicator(
                  onRefresh: controller.loadSessions,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    itemCount: controller.sessions.length,
                    separatorBuilder: (context, index) => const Padding(
                      padding: EdgeInsets.only(left: 85),
                      child: Divider(height: 1, color: Color(0xFFF5F5F5)),
                    ),
                    itemBuilder: (context, index) {
                      return _ChatListItem(session: controller.sessions[index]);
                    },
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const TextField(
        decoration: InputDecoration(
          hintText: "搜索",
          hintStyle: TextStyle(color: Colors.grey, fontSize: 15),
          prefixIcon: Icon(Icons.search, color: Colors.grey, size: 20),
          border: InputBorder.none,
          contentPadding: EdgeInsets.only(top: 2),
        ),
      ),
    );
  }
}

class _ChatListItem extends StatelessWidget {
  final ChatSession session;
  const _ChatListItem({required this.session});

  @override
  Widget build(BuildContext context) {
    String timeStr = _formatTime(session.lastUpdatedAt);

    // ✅ 适配：直接使用 ChatSession 中包含的 User 对象 (由 Controller 组装)
    final peer = session.otherUser;
    final avatarUrl = (peer?.avatarUrl != null && peer!.avatarUrl!.isNotEmpty)
        ? peer.avatarUrl
        : null;
    final name = peer?.username ?? "未知用户";

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ChatDetailPage(),
            settings: RouteSettings(
              arguments: {
                'otherUserId': session.otherUserId,
                'conversationId': session.conversationId,
                'otherUser': peer,
              },
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 55,
              height: 55,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0xFFE5E7EB),
                image: avatarUrl != null
                    ? DecorationImage(
                        image: NetworkImage(avatarUrl),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: avatarUrl == null
                  ? const Icon(Icons.person, color: Colors.white, size: 30)
                  : null,
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        timeStr,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          session.lastMessage,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (session.unreadCount > 0)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            "${session.unreadCount}",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    if (now.day == time.day) return DateFormat('HH:mm').format(time);
    if (now.difference(time).inDays < 7) {
      const weekdays = ["", "周一", "周二", "周三", "周四", "周五", "周六", "周日"];
      return weekdays[time.weekday];
    }
    return DateFormat('MM/dd').format(time);
  }
}
