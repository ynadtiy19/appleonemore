import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/social_notification_model.dart';
import '../pages/post_detail_page.dart';
import '../pages/user_profile_page.dart';

class NotificationHandlerService extends GetxService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  @override
  void onInit() {
    super.onInit();
    _initializeNotifications();
  }

  // 在 NotificationHandlerService 或初始化位置
  Future<void> requestPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
      await androidImplementation?.requestNotificationsPermission();
    }
  }

  /// 初始化通知设置
  Future<void> _initializeNotifications() async {
    await requestPermissions();
    // Android 设置: 使用 app_icon (需在 android/app/src/main/res/drawable 下有该图标)
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/guanbiziran');

    // iOS 设置
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );

    const WindowsInitializationSettings initializationSettingsWindows =
        WindowsInitializationSettings(
          appName: '观笔自然',
          appUserModelId: 'com.example.appleonemore', // 建议使用反域名
          guid: 'f3a9c4b2-8d7e-4c61-9f2e-6e5a8b1d3c47', // UUID v4
        );

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
          windows: initializationSettingsWindows, // 👈 关键
        );

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // 创建 Android 高优先级频道
    _createNotificationChannel();
  }

  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'social_alerts', // id
      '社交动态', // title
      description: '点赞、评论等社交通知',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      showBadge: true,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  /// 处理通知点击事件
  void _onNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      final Map<String, dynamic> data = jsonDecode(response.payload!);
      final String type = data['type'] ?? 'LIKE';

      if (type == 'FOLLOW') {
        // 🔥 如果是关注，跳转到用户主页
        final int triggerId = data['triggerId'];
        debugPrint("跳转到用户主页 ID: $triggerId");
        Navigator.push(
          Get.context!,
          MaterialPageRoute(
            builder: (context) => UserProfilePage(userId: triggerId),
          ),
        );
      } else {
        // 🔥 其他类型（点赞/评论），跳转到帖子详情
        final int postId = data['postId'];
        debugPrint("跳转到帖子 ID: $postId");
        Navigator.push(
          Get.context!,
          MaterialPageRoute(
            builder: (context) => PostDetailPage(postId: postId),
          ),
        );
      }
    }
  }

  /// 下载头像并保存为临时文件 (通知栏显示大图标必备)
  Future<String?> _downloadAndSaveFile(String? url, String fileName) async {
    if (url == null || url.isEmpty) return null;
    try {
      final Directory directory = await getTemporaryDirectory();
      final String filePath = '${directory.path}/$fileName';
      final http.Response response = await http.get(Uri.parse(url));
      final File file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);
      return filePath;
    } catch (e) {
      debugPrint("头像下载失败: $e");
      return null;
    }
  }

  /// 展示定制化的社交通知
  // 修改通知展示逻辑
  Future<void> handleIncomingNotification(SocialNotificationModel note) async {
    String title = '';
    String body = '';

    // 1. 根据类型定制文本
    if (note.type == 'LIKE') {
      title = '🔥 有人点赞了你';
      body = '${note.triggerName} 赞了你的帖子: "${note.postTitle}"';
    } else if (note.type == 'COMMENT') {
      title = '💬 有人评论了你的帖子';
      body = '${note.triggerName}: "${note.commentContent ?? ''}"';
    } else if (note.type == 'FOLLOW') {
      // 🔥 新增关注文案
      title = '🎉 有人关注了你';
      body = '${note.triggerName} 开始关注你了 🎉';
    }

    // 2. 准备大图标 (用户头像)
    final String? avatarPath = await _downloadAndSaveFile(
      note.triggerAvatar,
      'avatar_${note.triggerId}.png',
    );

    // 🔥 如果没有头像，使用默认的一个 assets 图标 (可选优化)
    // String? finalLargeIcon = avatarPath;

    // 3. 配置 Android 样式
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'social_alerts',
          '社交动态',
          channelDescription: '点赞、评论、关注等社交通知',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          color: const Color(0xFF6C63FF), // 使用比较潮的靛蓝色
          // 🔥 大图标逻辑：如果是关注，头像显示在右侧大图非常直观
          largeIcon: avatarPath != null
              ? FilePathAndroidBitmap(avatarPath)
              : null, // 如果没头像就不显示大图，只显示小图标
          // 使用 BigTextStyle
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: note.type == 'FOLLOW'
                ? '关注提醒'
                : (note.type == 'LIKE' ? '点赞提醒' : '评论提醒'),
            htmlFormatBigText: true, // 允许简单的 HTML 格式
            htmlFormatContentTitle: true,
          ),
        );

    // 4. 配置 iOS 样式
    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      attachments: avatarPath != null
          ? [DarwinNotificationAttachment(avatarPath)]
          : null,
      subtitle: note.type == 'FOLLOW' ? '你有了新粉丝' : note.postTitle,
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // 5. 显示通知
    await _notificationsPlugin.show(
      note.hashCode,
      title,
      body,
      platformDetails,
      // 🔥 Payload 增加 type 和 triggerId 用于跳转
      payload: jsonEncode({
        'postId': note.postId,
        'type': note.type,
        'triggerId': note.triggerId,
      }),
    );
  }
}
