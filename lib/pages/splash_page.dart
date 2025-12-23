import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../controllers/auth_controller.dart';
import '../services/db_service.dart';
import '../services/frontend_chat_service.dart';
import '../services/storage_service.dart';
import '../widgets/NatureInkPainter.dart';
import 'auth_page.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    _initApp();
  }

  // 在这里进行静默加载，同时 UI 已经在渲染
  Future<void> _initApp() async {
    final startTime = DateTime.now();

    // 异步初始化所有服务
    await Get.putAsync(() => StorageService().init());
    await Get.putAsync(() => DbService().init());
    // await Get.putAsync(() => AtChatService().init());

    debugPrint("📦 [System] 开始初始化服务...");

    // 3. 初始化前端聊天服务 (UI线程用: @gemini2banana)
    await Get.putAsync(() => FrontendChatService().init());

    // 此时 UI 线程已经准备好
    // 4. 🚀 启动后台隔离线程 (后台用: @dolphin9interim)
    // 这将开启一个新的线程，拥有独立的 DbService 和 BackendRelayService
    // await BackgroundRunner.startService();

    debugPrint("✅ [System] 所有服务初始化完成");

    final authC = Get.put(AuthController());
    await authC.checkAutoLogin();

    // 确保启动页至少显示 2.5 秒，保证意境完整性
    final elapsed = DateTime.now().difference(startTime);
    if (elapsed < const Duration(milliseconds: 2500)) {
      await Future.delayed(const Duration(milliseconds: 2500) - elapsed);
    }

    if (mounted) {
      Get.off(
        () => const AuthPage(),
        transition: Transition.fadeIn,
        duration: const Duration(milliseconds: 800),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFBFBFC), // 极淡的纸张色
      body: Stack(
        children: [
          // 背景动态意境
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return CustomPaint(
                painter: NatureInkPainter(_controller.value),
                size: Size.infinite,
              );
            },
          ),

          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 呼吸感的 Logo
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(seconds: 2),
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF4A6CF7).withOpacity(0.05),
                          blurRadius: 30,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.brush_outlined,
                      size: 36,
                      color: Color(0xFF4A6CF7),
                    ),
                  ),
                ),
                const SizedBox(height: 40),

                // 逐字渐显感的主标题
                const Text(
                  '观笔自然',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                    letterSpacing: 8, // 增加字间距更有意境
                    color: Color(0xFF2C3E50),
                  ),
                ),
                const SizedBox(height: 16),

                // 渐隐渐现的副标题
                Text(
                  'OBSERVE THE BRUSH  •  RETURN TO NATURE',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 2,
                    color: Colors.grey.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),

          // 底部加载提示
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '万物静观皆自得',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade400,
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
