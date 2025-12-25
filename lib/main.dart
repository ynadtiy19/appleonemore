import 'package:appleonemore/pages/ChatDetailPage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:get/get.dart';
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:kplayer/kplayer.dart';

import 'pages/splash_page.dart';
import 'services/db_service.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Player.boot();

  // 初始化服务 (顺序很重要)

  // await Get.putAsync(() => StorageService().init());
  // await Get.putAsync(() => DbService().init());
  // await Get.putAsync(() => AtChatService().init());

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 监听生命周期，更新在线状态
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!Get.isRegistered<StorageService>() || !Get.isRegistered<DbService>()) {
      debugPrint("⏳ 服务尚未就绪，忽略本次生命周期变更");
      return;
    }

    final storage = Get.find<StorageService>();
    final db = Get.find<DbService>();
    final uid = storage.getUserId();

    if (uid != null) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.detached) {
        db.updateOnlineStatus(uid, false);
      } else if (state == AppLifecycleState.resumed) {
        db.updateOnlineStatus(uid, true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: '观笔自然',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6B7280)),
        extensions: [
          GptMarkdownThemeData(
            brightness: Brightness.light,

            highlightColor: Colors.amber.withOpacity(0.3),

            h1: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              height: 1.5,
            ),
            h2: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
              height: 1.4,
            ),
            h3: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
            h4: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            h5: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            h6: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey,
            ),

            hrLineThickness: 1.5,
            hrLineColor: Colors.grey.shade300,

            linkColor: Colors.blueAccent,
            linkHoverColor: Colors.redAccent,
          ),
        ],

        // 👇 光标 + 选区颜色
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: Color(0xFFE57373), // 🌸 淡红色光标
          selectionColor: Color(0x33E57373), // 选中文本背景（带透明）
          selectionHandleColor: Color(0xFFE57373), // 拖动小圆点
        ),
        appBarTheme: const AppBarTheme(centerTitle: true),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      // 配置本地化，解决 Quill 报错
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        quill.FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en', 'US'), Locale('zh', 'CN')],
      home: const SplashPage(),
      getPages: [
        GetPage(name: '/chat_detail', page: () => const ChatDetailPage()),
      ],
    );
  }
}
