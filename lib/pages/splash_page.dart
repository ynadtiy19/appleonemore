import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'dart:math' as math;

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
    with TickerProviderStateMixin {
  // 背景水墨动画控制器
  late AnimationController _bgController;

  // Logo 浮动动画控制器
  late AnimationController _floatController;

  // 文本进场动画控制器
  late AnimationController _textController;

  @override
  void initState() {
    super.initState();

    // 1. 背景水墨流动动画
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    // 2. Logo 呼吸/浮动效果
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    // 3. 文本错落进场
    _textController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // 启动文本动画
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _textController.forward();
    });

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
    _bgController.dispose();
    _floatController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 定义淡雅的自然色调
    const Color paperBg = Color(0xFFFBFBFC); // 宣纸白
    const Color textDark = Color(0xFF2C3E50); // 墨色
    const Color accentGreen = Color(0xFFA8C8A6); // 淡雅的鼠尾草绿，呼应Logo

    return Scaffold(
      backgroundColor: paperBg,
      body: Stack(
        children: [
          // 1. 背景动态意境 (保留原有的 Painter)
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              return CustomPaint(
                painter: NatureInkPainter(_bgController.value),
                size: Size.infinite,
              );
            },
          ),

          // 2. 主体内容
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ---------------- LOGO 区域 ----------------
                AnimatedBuilder(
                  animation: _floatController,
                  builder: (context, child) {
                    // 使用正弦曲线制造轻微的上下浮动感，如叶子漂浮
                    final double offsetY = math.sin(_floatController.value * math.pi) * 8;
                    final double scale = 1.0 + (_floatController.value * 0.03);

                    return Transform.translate(
                      offset: Offset(0, offsetY),
                      child: Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 120, // 稍微加大尺寸以展示图片细节
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle, // 改为圆形背景更符合自然意境
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: accentGreen.withOpacity(0.2), // 绿色光晕
                                blurRadius: 40,
                                spreadRadius: 5,
                                offset: const Offset(0, 10),
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 10,
                                spreadRadius: 0,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(24.0), // 图片留白
                          child: Image.asset(
                            'images/playstore.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 50),

                // ---------------- 主标题：观笔自然 ----------------
                // 使用 Slide + Fade 组合动画
                SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.5),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: _textController,
                    curve: const Interval(0.0, 0.6, curve: Curves.easeOutCubic),
                  )),
                  child: FadeTransition(
                    opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                      CurvedAnimation(
                        parent: _textController,
                        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
                      ),
                    ),
                    child: const Text(
                      '观笔自然',
                      style: TextStyle(
                        fontSize: 32, // 字体稍大
                        fontWeight: FontWeight.w300,
                        letterSpacing: 12, // 宽字间距，营造空灵感
                        color: textDark,
                        fontFamily: "Serif", // 如果有宋体或衬线体效果更佳
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ---------------- 副标题：英文 ----------------
                SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.5),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: _textController,
                    curve: const Interval(0.3, 0.9, curve: Curves.easeOutCubic),
                  )),
                  child: FadeTransition(
                    opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                      CurvedAnimation(
                        parent: _textController,
                        curve: const Interval(0.3, 0.9, curve: Curves.easeOut),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 20, height: 1, color: accentGreen),
                        const SizedBox(width: 10),
                        Text(
                          'OBSERVE THE BRUSH • RETURN TO NATURE',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 3,
                            color: textDark.withOpacity(0.5),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Container(width: 20, height: 1, color: accentGreen),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. 底部加载提示 (淡入)
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(
                  parent: _textController,
                  curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
                ),
              ),
              child: Center(
                child: Column(
                  children: [
                    // 一个极小的加载指示器，颜色与主题融合
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.grey.withOpacity(0.3)
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '万物静观皆自得',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.withOpacity(0.6),
                        letterSpacing: 4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}