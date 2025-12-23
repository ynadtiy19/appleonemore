import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:at_client/at_client.dart';
import 'package:at_onboarding_cli/at_onboarding_cli.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:version/version.dart';

import '../models/chat_msg_model.dart';
import 'db_service.dart';
import 'storage_service.dart';

class FrontendChatService extends GetxService {
  static const String myAtsign = '@gemini2banana';
  static const String toAtsign = '@dolphin9interim';
  static const String nameSpace = 'atsign';
  static const String rootDomain = 'root.atsign.org';
  static const String groupConversationId = 'GROUP_GLOBAL'; // 群聊标识

  final MessageDeduplicator _deduplicator = MessageDeduplicator();

  final DbService _db = Get.find();
  final StorageService _storage = Get.find();

  final RxBool isOnboarded = false.obs;
  final RxBool isBackendAlive = false.obs;

  final Rxn<ChatMsgModel> incomingMessage = Rxn<ChatMsgModel>();
  final Rxn<ChatMsgModel> incomingGroupMessage =
      Rxn<ChatMsgModel>(); // 🔥 新增群消息监听

  final RxMap<int, bool> userOnlineStatus = <int, bool>{}.obs;
  Timer? _heartbeatTimer;

  // 🔥 修改 1: 将 atClient 声明为类的成员变量，以便全局访问
  AtClient? _atClient;

  Future<FrontendChatService> init() async {
    if (Platform.isAndroid) {
      await [Permission.storage, Permission.manageExternalStorage].request();
    }
    return this;
  }

  Future<void> authenticate() async {
    if (isOnboarded.value) return;
    AtServiceFactory? atServiceFactory;

    final supportDir = await getApplicationDocumentsDirectory();
    String keysPath = '${supportDir.path}/${myAtsign}_key.atKeys';

    // 🔥🔥🔥 新增逻辑：检查并复制密钥文件 🔥🔥🔥
    File keyFile = File(keysPath);
    if (!await keyFile.exists()) {
      debugPrint("⚠️ [Frontend] 密钥文件不存在，正在从 Assets 复制...");
      try {
        // 从 assets 读取数据
        final byteData = await rootBundle.load(
          'assets/keys/${myAtsign}_key.atKeys',
        );
        // 写入到手机的文档目录
        await keyFile.writeAsBytes(
          byteData.buffer.asUint8List(
            byteData.offsetInBytes,
            byteData.lengthInBytes,
          ),
        );
        debugPrint("✅ [Frontend] 密钥文件复制成功: $keysPath");
      } catch (e) {
        debugPrint("❌ [Frontend] 无法从 Assets 复制密钥文件: $e");
        debugPrint(
          "请确保 assets/@gemini2banana_key.atKeys 文件存在且已在 pubspec.yaml 中配置",
        );
        return; // 复制失败直接返回，避免后面报错
      }
    } else {
      debugPrint("ℹ️ [Frontend] 密钥文件已存在");
    }
    // 🔥🔥🔥 新增逻辑结束 🔥🔥🔥

    AtOnboardingPreference config = AtOnboardingPreference()
      ..namespace = nameSpace
      ..hiveStoragePath = '${supportDir.path}/.atsign/$myAtsign/storage'
      ..downloadPath = '${supportDir.path}/.atsign/files'
      ..isLocalStoreRequired = true
      ..rootDomain = rootDomain
      ..atKeysFilePath = keysPath
      ..commitLogPath = '${supportDir.path}/.atsign/$myAtsign/storage/commitLog'
      ..atProtocolEmitted = Version(2, 0, 0);

    AtOnboardingService onboardingService = AtOnboardingServiceImpl(
      myAtsign,
      config,
      atServiceFactory: atServiceFactory,
    );

    try {
      debugPrint("🤖 [Frontend] 开始认证: $myAtsign");
      bool authenticated = await onboardingService.authenticate();

      if (authenticated) {
        isOnboarded.value = true;
        isBackendAlive.value = true;
        debugPrint("✅ [Frontend] 认证成功");
        // 🔥 修改 2: 获取实例并赋值给成员变量 _atClient
        _atClient = AtClientManager.getInstance().atClient;
        _startFrontendMonitor(_atClient!);
        _startHeartbeatLoop();
      }
    } catch (e) {
      debugPrint("Auth Error: $e");
    }
  }

  // --- 发送逻辑 ---
  Future<bool> sendMessage({
    required String content,
    required int receiverId,
    required String receiverAtsign,
    required String conversationId, // 传入会话ID
    int type = 1,
  }) async {
    // 🔥 修改 3: 检查 _atClient 是否已初始化
    if (_atClient == null) {
      debugPrint("❌ [Frontend] 尚未认证，无法发送消息");
      return false;
    }

    final myId = _storage.getUserId();
    final myName = _storage.getUserName();
    final myAvatar = _storage.getUserAvatar();

    if (myId == null) return false;

    final msg = ChatMsgModel(
      id: const Uuid().v4(),
      conversationId: conversationId, // 使用传入的 ID (单聊/群聊)
      senderId: myId,
      senderName: myName,
      senderAvatar: myAvatar,
      receiverId: receiverId,
      receiverAtsign: receiverAtsign,
      content: content,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      type: type,
    );

    // 2. 如果是普通消息，先存库 (乐观更新)
    if (type != 99) {
      if (conversationId == groupConversationId) {
        await _db.saveGroupMessage(msg); // 存入群聊表
      } else {
        await _db.saveMessage(msg, isIncoming: false); // 存入单聊表
      }
    }

    final metaData = Metadata()
      ..isPublic = false
      ..isEncrypted = true
      ..namespaceAware = true;

    // 3. 触发通知
    final key = AtKey()
      ..key = 'attalk'
      ..sharedBy = myAtsign
      ..sharedWith = toAtsign
      ..namespace = nameSpace
      ..metadata = metaData;

    try {
      for (int retry = 0; retry < 3; retry++) {
        try {
          NotificationResult result = await _atClient!.notificationService
              .notify(
                NotificationParams.forUpdate(key, value: msg.toJson()),
                checkForFinalDeliveryStatus: false,
                waitForFinalDeliveryStatus: false,
              );

          if (result.atClientException != null) {
            retry++;
            await Future.delayed(Duration(milliseconds: (500 * (retry))));
          } else {
            debugPrint("前端发送成功: ${msg.toJson()}");
            break;
          }
        } catch (e) {
          debugPrint("发送失败: $e");
        }
      }
      return true;
    } catch (e) {
      debugPrint("❌ [Frontend] 发送触发失败: $e");
      return false;
    }
  }

  // --- 监听逻辑 ---
  void _startFrontendMonitor(AtClient atClient) {
    String regex = 'attalk.$nameSpace@';

    atClient.notificationService
        .subscribe(regex: regex, shouldDecrypt: true)
        .listen((notification) async {
          String? jsonVal = notification.value;
          debugPrint("📩 [Frontend] 收到消息: $jsonVal");
          // //使用土司显示出来
          // Get.showSnackbar(
          //   GetSnackBar(message: jsonVal, duration: Duration(seconds: 3)),
          // );
          if (jsonVal == null) return;

          try {
            Map<String, dynamic> payload = jsonDecode(jsonVal);
            ChatMsgModel msg = ChatMsgModel.fromMap(payload);

            // 🔥 2. 获取消息 ID
            String? msgId = msg.id;

            // 🔥 3. 执行去重检查
            if (_deduplicator.isDuplicate(msgId)) {
              debugPrint("🛡️ [Frontend] 拦截到重复消息，ID: $msgId");
              return;
            }

            int? myId = _storage.getUserId();
            if (myId == null) return;

            if (msg.senderId != myId) {
              // 🔥 判定是否为群聊消息
              if (msg.conversationId == groupConversationId) {
                debugPrint("👥 [Frontend] 收到群聊消息: ${msg.content}");

                // 1. 存入群聊表
                // await _db.saveGroupMessage(msg);
                // 2. 触发群聊监听
                incomingGroupMessage.value = msg;
                return;
              }

              // --- 以下是单聊逻辑 ---
              if (msg.type == 99 && msg.content == 'PING') {
                _sendHeartbeatAck(msg.senderId, msg.senderName);
                userOnlineStatus[msg.senderId] = true;
                return;
              }

              if (msg.type == 99 && msg.content == 'ACK') {
                userOnlineStatus[msg.senderId] = true;
                return;
              }

              debugPrint("📩 [Frontend] 收到单聊消息: ${msg.content}");
              await _db.saveMessage(msg, isIncoming: true);
              incomingMessage.value = msg;
            } else {
              debugPrint("💤 [Frontend] 忽略自己发的消息");
              // 忽略自己发的消息（回声）
            }
          } catch (e) {
            debugPrint("Msg Parse Error: $e");
          }
        });
  }

  // --- 心跳 ---
  void _startHeartbeatLoop() {
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) async {
      // 心跳逻辑省略...
    });
  }

  Future<void> _sendHeartbeatAck(int targetUserId, String targetAtsign) async {
    String resolvedAtsign = "@dolphin9interim";
    await sendMessage(
      content: 'ACK',
      receiverId: targetUserId,
      receiverAtsign: resolvedAtsign,
      conversationId: _db.getConversationId(
        targetUserId,
        _storage.getUserId()!,
      ),
      type: 99,
    );
  }

  @override
  void onClose() {
    _heartbeatTimer?.cancel();
    _deduplicator.clear();
    super.onClose();
  }
}

//uuu

/// 消息去重器
/// 用于在短时间内过滤掉具有相同 ID 的重复消息
class MessageDeduplicator {
  // 存储已处理的消息 ID
  final HashSet<String> _processedIds = HashSet<String>();

  // 缓存过期时间（默认 10 秒，足以覆盖网络重发或后端双推的时间差）
  final Duration cacheDuration;

  MessageDeduplicator({this.cacheDuration = const Duration(seconds: 10)});

  /// 检查消息是否重复
  /// 返回 true 表示是重复消息（应丢弃）
  /// 返回 false 表示是新消息（应处理）
  bool isDuplicate(String messageId) {
    if (_processedIds.contains(messageId)) {
      return true; // 已存在，是重复消息
    }

    // 不存在，标记为已处理
    _processedIds.add(messageId);

    // 设置定时器，在指定时间后移除该 ID，防止内存无限增长
    Future.delayed(cacheDuration, () {
      _processedIds.remove(messageId);
    });

    return false; // 不是重复消息
  }

  /// 清空所有缓存（在退出登录或销毁服务时调用）
  void clear() {
    _processedIds.clear();
  }
}
