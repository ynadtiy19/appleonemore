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

import '../models/AiRequestModel.dart';
import '../models/chat_msg_model.dart';
import '../models/social_notification_model.dart';
import 'db_service.dart';
import 'notification_handler_service.dart';
import 'storage_service.dart';

class FrontendChatService extends GetxService {
  static const String myAtsign = '@gemini2banana';
  static const String toAtsign = '@dolphin9interim';
  static const String aiServerAtsign = '@absolute3140';
  static const String nameSpace = 'atsign';
  static const String rootDomain = 'root.atsign.org';
  static const String groupConversationId = 'GROUP_GLOBAL'; // 群聊标识

  final MessageDeduplicator _deduplicator = MessageDeduplicator();
  final NotificationHandlerService _notificationHandler = Get.put(
    NotificationHandlerService(),
  );

  final DbService _db = Get.find();
  final StorageService _storage = Get.find();

  final RxBool isOnboarded = false.obs;
  final RxBool isBackendAlive = false.obs;

  final Rxn<ChatMsgModel> incomingMessage = Rxn<ChatMsgModel>();
  final Rxn<ChatMsgModel> incomingGroupMessage =
      Rxn<ChatMsgModel>(); // 🔥 新增群消息监听

  // 🔥 [AI] 新增 AI 响应监听变量
  final Rxn<AiResponseModel> incomingAiResponse = Rxn<AiResponseModel>();

  final RxMap<int, bool> userOnlineStatus = <int, bool>{}.obs;
  Timer? _heartbeatTimer;

  // 🔥 修改 1: 将 atClient 声明为类的成员变量，以便全局访问
  AtClient? _atClient;

  // 🔥 新增：持有通知服务的订阅
  StreamSubscription<dynamic>? _monitorSubscription;

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

  // =========================================================
  // 🔥 [AI] AI 聊天相关函数
  // =========================================================

  /// 发送 AI 聊天请求
  /// [content]: 当前用户输入
  /// [history]: 历史聊天记录 [{"role": "user", "parts": [{"text": "..."}]}, ...]
  /// [customApiKey]: (可选) 用户自行上传的 Key
  Future<bool> sendAiMessage({
    required String content,
    List<Map<String, dynamic>> history = const [],
    String? customApiKey,
  }) async {
    if (_atClient == null) {
      debugPrint("❌ [Frontend] 未认证，无法发送 AI 消息");
      return false;
    }

    final myId = _storage.getUserId();
    final myName = _storage.getUserName();
    final myAvatar = _storage.getUserAvatar();

    if (myId == null) return false;

    final aiRequest = AiRequestModel(
      requestId: myId.toString(),
      text: content,
      senderId: myId.toString(),
      senderName: myName,
      senderAvatar: myAvatar,
      history: history,
      userApiKey: customApiKey,
    );

    // 2. 构造 AtKey (通知给 Server)
    // Key 格式: ai_query.atsign@serverAtsign
    final metaData = Metadata()
      ..isPublic = false
      ..isEncrypted = true
      ..ttr = -1
      ..namespaceAware = true;

    final key = AtKey()
      ..key = 'ai_query'
      ..sharedBy = myAtsign
      ..sharedWith = aiServerAtsign
      ..namespace = nameSpace
      ..metadata = metaData;

    try {
      debugPrint("🤖 [Frontend] 正在请求 AI...");
      await _atClient!.notificationService.notify(
        NotificationParams.forUpdate(
          key,
          value: jsonEncode(aiRequest.toJson()),
        ),
        checkForFinalDeliveryStatus: false,
        waitForFinalDeliveryStatus: false,
      );
      return true;
    } catch (e) {
      debugPrint("❌ [Frontend] AI 请求发送失败: $e");
      return false;
    }
  }

  // --- 发送社交通知 (新增函数) ---
  Future<bool> sendSocialNotification({
    required int postId,
    required String postTitle,
    String? postImage,
    required int creatorId, // 帖子作者ID
    required String? creatorName, // 帖子作者ID
    required String type, // 'LIKE' or 'COMMENT'
    String? commentContent,
  }) async {
    if (_atClient == null) {
      debugPrint("❌ [Frontend] 未认证，无法发送通知");
      return false;
    }

    final myId = _storage.getUserId();
    final myName = _storage.getUserName();
    final myAvatar = _storage.getUserAvatar();

    if (myId == null) return false;

    // 构建通知模型
    final notification = SocialNotificationModel(
      id: const Uuid().v4(),
      type: type,
      postId: postId,
      postTitle: postTitle,
      postImage: postImage,
      creatorId: creatorId,
      creatorName: creatorName,
      triggerId: myId,
      triggerName: myName,
      triggerAvatar: myAvatar,
      commentContent: commentContent,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final metaData = Metadata()
      ..isPublic = false
      ..isEncrypted = true
      ..ttr = -1
      ..namespaceAware = true;

    // 通知的 Key，区分于聊天的 'attalk'，这里用 'atsocial'
    // 或者为了复用监听流，继续使用 'attalk' 但依靠内部 dataType 区分
    // 这里为了简便复用同一个监听 Regex，我们继续使用 'attalk' Key
    final key = AtKey()
      ..key = 'atsocial'
      ..sharedBy = myAtsign
      ..sharedWith = toAtsign
      ..namespace = nameSpace
      ..metadata = metaData;

    try {
      await _atClient!.notificationService.notify(
        NotificationParams.forUpdate(key, value: notification.toJson()),
        checkForFinalDeliveryStatus: false,
        waitForFinalDeliveryStatus: false,
      );
      debugPrint("🔔 [Frontend] 社交通知发送成功: ${notification.type}");
      return true;
    } catch (e) {
      debugPrint("❌ [Frontend] 社交通知发送失败: $e");
      return false;
    }
  }

  // --- 发送关注通知 ---
  Future<bool> sendFollowNotification({required int targetUserId}) async {
    if (_atClient == null) return false;

    final myId = _storage.getUserId();
    final myName = _storage.getUserName();
    final myAvatar = _storage.getUserAvatar();

    if (myId == null) return false;

    final notification = SocialNotificationModel(
      id: const Uuid().v4(),
      type: 'FOLLOW', // 🔥 类型为 FOLLOW
      postId: 0, // 关注与帖子无关
      postTitle: '',
      creatorId: targetUserId,
      triggerId: myId,
      triggerName: myName,
      triggerAvatar: myAvatar,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    );

    final metaData = Metadata()
      ..isPublic = false
      ..isEncrypted = true
      ..ttr = -1
      ..namespaceAware = true;

    // 复用 atsocial key，后端会自动转发
    final key = AtKey()
      ..key = 'atsocial'
      ..sharedBy = myAtsign
      ..sharedWith = toAtsign
      ..namespace = nameSpace
      ..metadata = metaData;

    try {
      await _atClient!.notificationService.notify(
        NotificationParams.forUpdate(key, value: notification.toJson()),
        checkForFinalDeliveryStatus: false,
        waitForFinalDeliveryStatus: false,
      );
      debugPrint("🔔 [Frontend] 关注通知发送成功");
      return true;
    } catch (e) {
      debugPrint("❌ [Frontend] 关注通知发送失败: $e");
      return false;
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
      ..ttr = -1
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
    String combinedRegex = '(attalk|atsocial|ai_reply).*\\.$nameSpace@';

    debugPrint("🎧 [Frontend] 开始监听所有通道: $combinedRegex");

    _monitorSubscription = atClient.notificationService
        .subscribe(regex: combinedRegex, shouldDecrypt: true)
        .listen((notification) async {
          String? jsonVal = notification.value;
          if (jsonVal == null) return;

          // 获取 Key 的前缀部分
          // 示例 Key: ai_reply.10086.atsign@gemini2banana
          String fullKey = notification.key;
          String keyType = '';

          if (fullKey.contains('attalk')) {
            keyType = 'attalk';
          } else if (fullKey.contains('atsocial')) {
            keyType = 'atsocial';
          } else if (fullKey.contains('ai_reply')) {
            keyType = 'ai_reply';
          }

          try {
            Map<String, dynamic> payload = jsonDecode(jsonVal);

            // ============ 分支 1: AI 回复 ============
            if (keyType == 'ai_reply') {
              debugPrint("🤖 [Frontend] 收到 AI 回复: $payload");
              final aiResponse = AiResponseModel.fromMap(payload);

              final myId = _storage.getUserId().toString();
              if (aiResponse.requestId == myId) {
                // 3. 更新响应式变量，UI 自动刷新
                incomingAiResponse.value = aiResponse;

                // 4. (可选) 可以在这里直接存入本地数据库
                // 构造一个 ChatMsgModel 存入本地，假装是 AI 发的消息
                // await _saveAiMessageToLocalDb(aiResponse);
              } else {
                debugPrint("⚠️ 收到了不属于当前用户的 AI 回复 (ID mismatch)");
              }
              return;
            }

            // ============ 分支 2: 聊天消息 (attalk) ============
            if (keyType == 'attalk') {
              ChatMsgModel msg = ChatMsgModel.fromMap(payload);
              String? msgId = msg.id;

              if (_deduplicator.isDuplicate(msgId)) {
                debugPrint("❌ [Frontend] 跳过重复消息");
                return;
              }

              int? myId = _storage.getUserId();
              if (myId == null) return;

              if (msg.senderId != myId) {
                if (msg.conversationId == groupConversationId) {
                  debugPrint("👥 [Frontend] 收到群聊消息: $payload");
                  incomingGroupMessage.value = msg;
                  return;
                }

                if (msg.type == 99 && msg.content == 'PING') {
                  debugPrint("🏓 [Frontend] 收到心跳包: $payload");
                  _sendHeartbeatAck(msg.senderId, msg.senderName);
                  userOnlineStatus[msg.senderId] = true;
                  return;
                }
                if (msg.type == 99 && msg.content == 'ACK') {
                  debugPrint("🏓 [Frontend] 收到心跳包 ACK: $payload");
                  userOnlineStatus[msg.senderId] = true;
                  return;
                }

                await _db.saveMessage(msg, isIncoming: true);
                incomingMessage.value = msg;
                debugPrint("👤 [Frontend] 收到个人消息: $payload");
              }
              return;
            }

            // ============ 分支 3: 社交通知 (atsocial) ============
            if (keyType == 'atsocial') {
              SocialNotificationModel note = SocialNotificationModel.fromMap(
                payload,
              );

              debugPrint("👥 [Frontend] 收到社交通知: $payload");
              if (_deduplicator.isDuplicate(note.id)) {
                debugPrint("❌ [Frontend] 跳过重复消息");
                return;
              }

              int? myId = _storage.getUserId();
              if (myId != null && note.triggerId == myId) {
                return;
              }
              _notificationHandler.handleIncomingNotification(note);
              return;
            }
          } catch (e) {
            debugPrint("❌ [Frontend] 消息解析错误 ($keyType): $e");
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
    debugPrint(" M[Frontend] 销毁 Atsign 服务...");

    _heartbeatTimer?.cancel();

    _monitorSubscription?.cancel();

    _deduplicator.clear();

    isOnboarded.value = false;
    isBackendAlive.value = false;
    _atClient = null;

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
