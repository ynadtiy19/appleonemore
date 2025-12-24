import 'dart:math' as math;

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

class _SplashPageState extends State<SplashPage> with TickerProviderStateMixin {
  // 背景意境动画控制器
  late AnimationController _bgController;

  // 标志物摆动与缩放控制器（模拟微风中的叶子）
  late AnimationController _swayController;

  // 文字与元素显影控制器
  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();

    // 1. 背景意境动画：平缓的水墨流动
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    // 2. 标志物：模拟自然中的摇曳感与呼吸感
    _swayController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);

    // 3. 元素进场：柔和的缩放与淡入
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // 延时启动进场动画
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _fadeController.forward();
    });

    _initApp();
  }

  // --- 完整保留初始化逻辑 ---
  Future<void> _initApp() async {
    final startTime = DateTime.now();

    // 异步初始化所有服务
    await Get.putAsync(() => StorageService().init());
    await Get.putAsync(() => DbService().init());

    debugPrint("📦 [System] 开始初始化服务...");

    // 初始化前端聊天服务
    await Get.putAsync(() => FrontendChatService().init());

    debugPrint("✅ [System] 所有服务初始化完成");

    final authC = Get.put(AuthController());
    await authC.checkAutoLogin();

    // 确保启动页显示时间，保证意境完整性
    final elapsed = DateTime.now().difference(startTime);
    if (elapsed < const Duration(milliseconds: 3500)) {
      await Future.delayed(const Duration(milliseconds: 3500) - elapsed);
    }

    if (mounted) {
      Get.off(
        () => const AuthPage(),
        transition: Transition.fadeIn,
        duration: const Duration(milliseconds: 1000),
      );
    }
  }

  @override
  void dispose() {
    _bgController.dispose();
    _swayController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 重新定义色调：黛青、云松、烟墨
    const Color bgPaper = Color(0xFFF2F4F1); // 烟云灰白
    const Color inkPrimary = Color(0xFF1A1A1A); // 深潭墨色
    const Color pineGreen = Color(0xFF5D7268); // 云松黛绿
    const Color leafLight = Color(0xFF8DA399); // 溪水淡青

    return Scaffold(
      backgroundColor: bgPaper,
      body: Stack(
        children: [
          // 1. 背景动态意境
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              return CustomPaint(
                painter: NatureInkPainter(_bgController.value),
                size: Size.infinite,
              );
            },
          ),

          // 2. 核心视觉内容
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ---------------- 标志物区域 ----------------
                AnimatedBuilder(
                  animation: _swayController,
                  builder: (context, child) {
                    final double rotation =
                        math.sin(_swayController.value * math.pi) * 0.05;
                    final double scale =
                        1.0 +
                        (math.sin(_swayController.value * math.pi) * 0.04);

                    return FadeTransition(
                      opacity: CurvedAnimation(
                        parent: _fadeController,
                        curve: const Interval(0.0, 0.5, curve: Curves.easeIn),
                      ),
                      child: Transform.rotate(
                        angle: rotation,
                        child: Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                20,
                              ), // 👈 正方形圆角
                              boxShadow: [
                                BoxShadow(
                                  color: pineGreen.withOpacity(0.15),
                                  blurRadius: 30,
                                  spreadRadius: 2,
                                ),
                                BoxShadow(
                                  color: inkPrimary.withOpacity(0.02),
                                  blurRadius: 10,
                                  offset: const Offset(0, 5),
                                ),
                              ],
                              image: const DecorationImage(
                                image: AssetImage('images/playstore.png'),
                                fit: BoxFit.cover, // 👈 关键：填满且裁剪
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                const SizedBox(height: 60),

                // ---------------- 主标题 ----------------
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _fadeController,
                    curve: const Interval(0.3, 0.8, curve: Curves.easeIn),
                  ),
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.95, end: 1.0).animate(
                      CurvedAnimation(
                        parent: _fadeController,
                        curve: const Interval(0.3, 0.8, curve: Curves.easeIn),
                      ),
                    ),
                    child: const Text(
                      '观笔自然',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w200,
                        letterSpacing: 14,
                        color: inkPrimary,
                        fontFamily: "Serif",
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 25),

                // ---------------- 副标题 ----------------
                FadeTransition(
                  opacity: CurvedAnimation(
                    parent: _fadeController,
                    curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDecorativeLine(pineGreen, true),
                      const SizedBox(width: 15),
                      const Text(
                        '以心观尘 · 笔墨入境',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 6,
                          color: pineGreen,
                        ),
                      ),
                      const SizedBox(width: 15),
                      _buildDecorativeLine(pineGreen, false),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 3. 底部加载意境
          Positioned(
            bottom: 70,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: CurvedAnimation(
                parent: _fadeController,
                curve: const Interval(0.7, 1.0, curve: Curves.easeIn),
              ),
              child: Center(
                child: Column(
                  children: [
                    // 自定义中式简约加载点
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(3, (index) {
                        return AnimatedBuilder(
                          animation: _swayController,
                          builder: (context, child) {
                            final delay = index * 0.2;
                            final dotOpacity =
                                (math.sin(
                                      (_swayController.value * 2 * math.pi) +
                                          delay,
                                    ) +
                                    1) /
                                2;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: inkPrimary.withOpacity(dotOpacity * 0.3),
                              ),
                            );
                          },
                        );
                      }),
                    ),
                    const SizedBox(height: 15),
                    Text(
                      '万物静观皆自得',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w300,
                        color: pineGreen.withOpacity(0.7),
                        letterSpacing: 5,
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

  // 装饰性线条组件
  Widget _buildDecorativeLine(Color color, bool isLeft) {
    return Container(
      width: 25,
      height: 0.5,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isLeft
              ? [color.withOpacity(0), color]
              : [color, color.withOpacity(0)],
        ),
      ),
    );
  }
}

// 曲线扩展，用于更平滑的进场效果
extension on Curves {
  static const Curve outProposed = Cubic(0.2, 0.0, 0.0, 1.0);
}
