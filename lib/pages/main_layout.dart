import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';

import '../controllers/main_controller.dart';
import 'SesameChatPage.dart';
import 'group_chat_page.dart';
import 'home_page.dart';
import 'payment_page.dart';
import 'profile_page.dart';

class MainLayout extends StatelessWidget {
  const MainLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Get.put(MainController());
    final pages = [
      const HomePage(),
      const GroupChatPage(),
      const PaymentPage(),
      const SesameChatPage(),
      const ProfilePage(),
    ];

    return Scaffold(
      body: Obx(
        () => IndexedStack(index: c.currentIndex.value, children: pages),
      ),
      bottomNavigationBar: Obx(
        () => NavigationBar(
          selectedIndex: c.currentIndex.value,
          onDestinationSelected: c.changePage,
          destinations: const [
            NavigationDestination(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedHome01,
                color: Color(0xFFB6C0F4),
                size: 30.0,
              ),
              label: "首页",
            ),
            NavigationDestination(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedBubbleChat,
                color: Color(0xFFB6C0F4),
                size: 30.0,
              ),
              label: "聊天",
            ),
            NavigationDestination(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedPaypal,
                color: Color(0xFFB6C0F4),
                size: 30.0,
              ),
              label: "订单",
            ),
            NavigationDestination(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedAiAudio,
                color: Color(0xFFB6C0F4),
                size: 30.0,
              ),
              label: "语音",
            ),
            NavigationDestination(
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedUser,
                color: Color(0xFFB6C0F4),
                size: 30.0,
              ),
              label: "我的",
            ),
          ],
        ),
      ),
    );
  }
}
