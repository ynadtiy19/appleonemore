import 'dart:async';
import 'dart:io';

import 'package:appleonemore/services/storage_service.dart';
import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:at_utils/at_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:version/version.dart';

import 'db_service.dart';

class AtChatService extends GetxService {
  // ==========================================
  // 🔴 根据打包需求修改此处 AtSign
  // 管理员包: from=@gemini2banana, to=@dolphin9interim//电脑
  // 用户包:   from=@dolphin9interim, to=@gemini2banana//手机
  // ==========================================
  static const String fromAtsign = '@gemini2banana';
  static const String toAtsign = '@dolphin9interim';

  static const String nameSpace = 'atsign';
  static const String rootDomain = 'root.atsign.org';

  final RxBool isOnboarded = false.obs;
  final RxBool isHeartbeatSuccess = false.obs;
  final RxList<String> messages = <String>[].obs;

  // 移除直接初始化，改为 getter 或在 authenticate 后获取
  // AtClient uatClient = AtClientManager.getInstance().atClient; // ❌ 错误来源

  // ✅ 正确方式：使用 getter 动态获取单例
  AtClient get uatClient => AtClientManager.getInstance().atClient;

  StreamSubscription? _monitorSub;

  Future<AtChatService> init() async {
    if (Platform.isAndroid) {
      await [Permission.storage, Permission.manageExternalStorage].request();
    }
    return this;
  }

  Future<String> _getLocalKeysPath() async {
    String filename = '${fromAtsign}_key.atKeys';
    if (Platform.isWindows) {
      if (kDebugMode) {
        print('在编辑器中运行，直接返回 assets 路径');
        return 'assets/keys/$filename';
      }
      return 'data/flutter_assets/assets/keys/$filename';
    }

    final dir = await getApplicationDocumentsDirectory();
    final localPath = '${dir.path}/$filename';
    final file = File(localPath);

    if (!await file.exists()) {
      try {
        final byteData = await rootBundle.load('assets/keys/$filename');
        await file.writeAsBytes(byteData.buffer.asUint8List());
        debugPrint("Key file copied to: $localPath");
      } catch (e) {
        debugPrint("Key file load error: $e");
      }
    }
    return localPath;
  }

  Future<void> authenticate() async {
    if (isOnboarded.value) return;

    AtServiceFactory? atServiceFactory;

    String keysPath = await _getLocalKeysPath();
    final supportDir = await getApplicationDocumentsDirectory();

    AtOnboardingPreference config = AtOnboardingPreference()
      ..namespace = nameSpace
      ..hiveStoragePath = '${supportDir.path}/.atsign/$fromAtsign/storage'
      ..downloadPath = '${supportDir.path}/.atsign/files'
      ..isLocalStoreRequired = true
      ..rootDomain = rootDomain
      ..fetchOfflineNotifications = true
      ..atKeysFilePath = keysPath
      ..commitLogPath =
          '${supportDir.path}/.atsign/$fromAtsign/storage/commitLog'
      ..atProtocolEmitted = Version(2, 0, 0);

    AtOnboardingService onboardingService = AtOnboardingServiceImpl(
      fromAtsign,
      config,
      atServiceFactory: atServiceFactory,
    );

    try {
      debugPrint("开始认证...");
      // authenticate 会自动处理 AtClientManager 的初始化
      bool authenticated = await onboardingService.authenticate();

      if (authenticated) {
        isOnboarded.value = true;
        debugPrint("认证成功: $fromAtsign");
        _startMonitor();
      } else {
        debugPrint("认证失败");
      }
    } catch (e) {
      debugPrint("Auth Error: $e");
    }
  }

  void _startMonitor() {
    debugPrint("开始监听消息...");
    // 💡 修改正则：监听所有以 attalk 开头的 key
    // 匹配格式：attalk.<convId>.<namespace>@<atsign>
    String regex = 'attalk\\..*\\.$nameSpace@';

    final AtSignLogger logger = AtSignLogger('atTalk');
    logger.hierarchicalLoggingEnabled = true;
    logger.logger.level = Level.SHOUT;

    // 此时 uatClient 已经可用
    _monitorSub = uatClient.notificationService
        .subscribe(regex: regex, shouldDecrypt: true)
        .listen((notification) async {
          String? fullKey = notification.key;
          String? value = notification.value;
          // if (value != null && value.isNotEmpty) {
          //   // 心跳回执处理
          //   if (value == "PING_ACK") {
          //     isHeartbeatSuccess.value = true;
          //     debugPrint("❤️ 收到心跳回执");
          //   } else if (value == "PING") {
          //     // 收到 Ping，自动回 Ack
          //     sendMessage("PING_ACK");
          //   } else {
          //     // 正常消息
          //     messages.add("Ta: $value");
          //   }
          // }

          if (value != null && value.isNotEmpty) {
            if (fullKey.contains("system_status")) {
              if (value == "PING") {
                // 收到 PING 可以选择回 PING_ACK，或者单纯不予理会
                debugPrint("监听到探测包");
              }
              return;
            }
            // 1. 解析出 conversation_id
            // 移除命名空间和前缀，提取中间的 1_2
            final parts = fullKey.split('.');
            if (parts.length < 2) return;
            String convId = parts[1]; // 拿到 "1_2"

            // 2. 写入 LibSQL 数据库 (持久化)
            final db = Get.find<DbService>();
            final storage = Get.find<StorageService>();
            final myId = storage.getUserId();

            if (myId != null) {
              // 解析出对方的 UID (假设 convId 格式为 5_10)
              List<String> uids = convId.split('_');
              int otherId = int.parse(
                uids.first == myId.toString() ? uids.last : uids.first,
              );

              messages.add("Ta: $value");
            }
          }
        });

    _startHeartbeat();
  }

  Future<bool> sendMessage(String msg, {String? conversationId}) async {
    if (msg.isEmpty) return false;

    // 确保已认证
    if (!isOnboarded.value) {
      debugPrint("尚未认证，无法发送消息");
      return false;
    }

    // 💡 应用 conversation_id：
    // 如果是心跳，传 "system_status"；如果是聊天，传真实的 "1_2"
    final String cid = conversationId ?? "default_chat";
    bool success = false;

    final key = AtKey()
      ..key = 'attalk.$cid'
      ..sharedBy = fromAtsign
      ..sharedWith = toAtsign
      ..namespace = nameSpace
      ..metadata = (Metadata()
        ..isPublic = false
        ..isEncrypted = true
        ..ttl = 10000
        ..namespaceAware = true);

    for (int retry = 0; retry < 3; retry++) {
      try {
        NotificationResult result = await uatClient.notificationService.notify(
          NotificationParams.forUpdate(key, value: msg),
          waitForFinalDeliveryStatus: false,
          checkForFinalDeliveryStatus: false,
        );

        if (result.atClientException != null) {
          retry++;
          await Future.delayed(Duration(milliseconds: (500 * (retry))));
        } else {
          if (cid != "system_status" && !msg.startsWith("PING")) {
            messages.add("Me: $msg");
          }
          debugPrint("发送成功: $msg");
          success = true;
          break;
        }
      } catch (e) {
        debugPrint("发送失败: $e");
      }
    }

    return success;
  }

  Future<void> _startHeartbeat() async {
    debugPrint("开始发送心跳...");
    // 简单的三次握手心跳
    for (int i = 0; i < 3; i++) {
      bool sent = await sendMessage("PING", conversationId: "system_status");
      if (sent) {
        // 简化逻辑：发送成功即视为在线
        isHeartbeatSuccess.value = true;
        debugPrint("心跳发送成功");
        break;
      }
      await Future.delayed(const Duration(seconds: 2));
    }
  }
}
