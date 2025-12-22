import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';

import 'backend_relay_service.dart';
import 'db_service.dart';
import 'storage_service.dart';

class BackgroundRunner {
  static Isolate? _backgroundIsolate;
  static final ReceivePort _receivePort = ReceivePort();

  static Future<void> startService() async {
    if (_backgroundIsolate != null) return;
    debugPrint("🚀 [Main] 准备启动后台隔离线程...");

    RootIsolateToken? rootToken = RootIsolateToken.instance;
    if (rootToken == null) return;

    String keyPath = await _prepareKeyFile();

    int? myId;
    try {
      final storage = Get.find<StorageService>();
      myId = storage.getUserId();
    } catch (e) {
      debugPrint("Main thread 获取 ID 失败: $e");
    }

    try {
      _backgroundIsolate = await Isolate.spawn(
        _isolateEntryPoint,
        _IsolateArgs(
          rootToken: rootToken,
          sendPort: _receivePort.sendPort,
          keyFilePath: keyPath,
          currentUserId: myId,
        ),
      );

      _receivePort.listen((message) {
        debugPrint("📬 [Main received]: $message");
      });
    } catch (e) {
      debugPrint("❌ 启动隔离线程失败: $e");
    }
  }

  static void stopService() {
    if (_backgroundIsolate != null) {
      _backgroundIsolate!.kill(priority: Isolate.immediate);
      _backgroundIsolate = null;
    }
  }

  static Future<String> _prepareKeyFile() async {
    const String filename = '@dolphin9interim_key.atKeys';
    // ... (保持原有的路径处理逻辑不变) ...
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (kDebugMode) return 'assets/keys/$filename';
      return 'data/flutter_assets/assets/keys/$filename';
    }
    final dir = await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/$filename';
    final file = File(localPath);
    if (!await file.exists()) {
      try {
        final byteData = await rootBundle.load('assets/keys/$filename');
        await file.writeAsBytes(byteData.buffer.asUint8List());
      } catch (e) {
        debugPrint("Key Error: $e");
      }
    }
    return localPath;
  }

  // =========================================================
  // 🚪 隔离线程入口
  // =========================================================
  @pragma('vm:entry-point')
  static void _isolateEntryPoint(_IsolateArgs args) async {
    // A. 初始化 Platform Channels
    BackgroundIsolateBinaryMessenger.ensureInitialized(args.rootToken);

    debugPrint("👻 [Isolate] 纯 Dart 环境初始化 (无 UI)...");

    try {
      // 🔴 关键修改：不要使用 Get.put，直接实例化

      // 1. 初始化 DbService
      final dbService = DbService();
      await dbService.init();
      debugPrint("👻 [Isolate] DB 服务已连接");

      // 2. 初始化 BackendRelayService
      final backendService = BackendRelayService();

      // 3. 手动注入依赖！(BackendRelayService 需要新增此方法)
      backendService.injectDependencies(dbService);

      // 4. 初始化配置
      await backendService.initInIsolate(
        args.keyFilePath,
        currentUserId: args.currentUserId,
      );

      // 5. 开始认证
      await backendService.authenticateRelay();

      args.sendPort.send("SERVICE_STARTED");
    } catch (e, stack) {
      debugPrint("❌ [Isolate Error] 后台崩溃: $e\n$stack");
      args.sendPort.send("SERVICE_CRASHED: $e");
    }
  }
}

class _IsolateArgs {
  final RootIsolateToken rootToken;
  final SendPort sendPort;
  final String keyFilePath;
  final int? currentUserId; // 新增

  _IsolateArgs({
    required this.rootToken,
    required this.sendPort,
    required this.keyFilePath,
    this.currentUserId,
  });
}
