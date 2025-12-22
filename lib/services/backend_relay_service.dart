import 'dart:async';
import 'dart:convert';

import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:version/version.dart';

import '../models/chat_msg_model.dart';
import 'db_service.dart';
import 'storage_service.dart';

class BackendRelayService extends GetxService {
  // 配置：当前设备的 AtSign (后台身份)
  static const String myAtsign = '@dolphin9interim';
  static const String toAtsign = '@gemini2banana';
  static const String nameSpace = 'atsign';
  static const String rootDomain = 'root.atsign.org';

  final RxBool isRelayReady = false.obs;

  AtClient get relayClient => AtClientManager.getInstance().atClient;

  // 🔴 1. 新增：用于 Isolate 环境的变量
  DbService? _injectedDb;
  String? _forcedKeyPath;
  int? _forcedUserId; // 在后台线程中，我们需要手动传入 ID

  // 🔴 2. 新增：依赖注入方法 (供 BackgroundRunner 调用)
  void injectDependencies(DbService db) {
    _injectedDb = db;
  }

  // 🔴 3. 新增：Isolate 初始化方法 (供 BackgroundRunner 调用)
  // 我们需要传入 keyPath，最好也传入当前用户的 ID，以便判断 senderId
  Future<void> initInIsolate(String keyPath, {int? currentUserId}) async {
    _forcedKeyPath = keyPath;
    _forcedUserId = currentUserId;
    debugPrint("🕵️ [Backend] Isolate模式已配置: Path=$keyPath, UID=$currentUserId");
  }

  /// 普通初始化 (GetX 模式)
  Future<BackendRelayService> init() async {
    return this;
  }

  // 获取当前用户 ID 的辅助方法
  // 逻辑：如果有强制传入的ID(Isolate)，用强制的；否则尝试从 GetX Storage 获取
  int? _getCurrentUserId() {
    if (_forcedUserId != null) return _forcedUserId;
    try {
      final storage = Get.find<StorageService>();
      return storage.getUserId();
    } catch (e) {
      debugPrint(
        "⚠️ [Backend] 无法获取 UserID (非 Isolate 模式请确保 StorageService 已启动)",
      );
      return null;
    }
  }

  Future<void> authenticateRelay() async {
    // 🔴 4. 修改：路径获取逻辑
    String keysPath;
    String storagePath;
    String downloadPath;

    if (_forcedKeyPath != null) {
      // Isolate 模式
      final dir = await getApplicationDocumentsDirectory(); // Isolate 中获取目录是安全的
      keysPath = _forcedKeyPath!;
      storagePath = '${dir.path}/.atsign/$myAtsign/relay_storage';
      downloadPath = '${dir.path}/.atsign/relay_files';
    } else {
      // 普通模式
      final supportDir = await getApplicationDocumentsDirectory();
      keysPath = '${supportDir.path}/${myAtsign}_key.atKeys';
      storagePath = '${supportDir.path}/.atsign/$myAtsign/relay_storage';
      downloadPath = '${supportDir.path}/.atsign/relay_files';
    }

    AtOnboardingPreference config = AtOnboardingPreference()
      ..namespace = nameSpace
      ..hiveStoragePath = storagePath
      ..downloadPath = downloadPath
      ..isLocalStoreRequired = true
      ..rootDomain = rootDomain
      ..atKeysFilePath = keysPath
      ..atProtocolEmitted = Version(2, 0, 0);

    AtOnboardingService onboardingService = AtOnboardingServiceImpl(
      myAtsign,
      config,
    );

    try {
      debugPrint("🕵️ [Backend] 开始认证: $myAtsign");
      bool authenticated = await onboardingService.authenticate();

      if (authenticated) {
        isRelayReady.value = true;
        debugPrint("✅ [Backend] 认证成功，启动转发监听");
        _startRelayMonitor();
      }
    } catch (e) {
      debugPrint("❌ [Backend] Auth Error: $e");
    }
  }

  void _startRelayMonitor() {
    String regex = 'attalk.$nameSpace@';

    relayClient.notificationService
        .subscribe(regex: regex, shouldDecrypt: true)
        .listen((notification) async {
          String? jsonValue = notification.value;
          debugPrint("📩 [Backend] 收到消息: $jsonValue");
          if (jsonValue == null) return;

          try {
            Map<String, dynamic> payload = jsonDecode(jsonValue);
            ChatMsgModel msg = ChatMsgModel.fromMap(payload);

            // 使用兼容的方法获取 ID
            int? myId = _getCurrentUserId();

            // 如果是在后台线程且没有传入 ID，我们可能无法过滤消息
            // 建议：如果 _forcedUserId 为 null，且 msg.senderId > 0，也可以尝试转发
            // 但为了安全，最好在 BackgroundRunner 里传入 ID

            await _relayMessageToRemote(msg);
            // if (myId != null && msg.senderId == myId) {
            //   if (msg.receiverAtsign.isNotEmpty &&
            //       msg.receiverAtsign != myAtsign) {
            //     debugPrint("🚀 [Backend] 转发消息 -> ${msg.receiverAtsign}");
            //     await _relayMessageToRemote(msg);
            //   }
            // } else {
            //   debugPrint("💤 [Backend] 忽略入站消息");
            // }
          } catch (e) {
            debugPrint("❌ [Backend] 处理异常: $e");
          }
        });
  }

  Future<void> _relayMessageToRemote(ChatMsgModel msg) async {
    final key = AtKey()
      ..key = 'attalk'
      ..sharedBy = myAtsign
      ..sharedWith = toAtsign
      ..namespace = nameSpace
      ..metadata = (Metadata()..ttr = -1);

    try {
      for (int retry = 0; retry < 3; retry++) {
        try {
          NotificationResult result = await relayClient.notificationService
              .notify(
                NotificationParams.forUpdate(key, value: msg.toJson()),
                checkForFinalDeliveryStatus: false,
                waitForFinalDeliveryStatus: false,
              );

          if (result.atClientException != null) {
            retry++;
            await Future.delayed(Duration(milliseconds: (500 * (retry))));
          } else {
            debugPrint("中转发送成功: ${msg.toJson()}");
            break;
          }
        } catch (e) {
          debugPrint("发送失败: $e");
        }
      }
    } catch (e) {
      debugPrint("❌ [Backend] 转发失败: $e");
    }
  }
}
