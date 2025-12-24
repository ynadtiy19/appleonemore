import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/social_notification_model.dart';
import '../pages/post_detail_page.dart';

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

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
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
      final int postId = data['postId'];
      debugPrint("跳转到帖子 ID: $postId");
      // 这里可以执行跳转逻辑
      Navigator.push(
        Get.context!,
        MaterialPageRoute(builder: (context) => PostDetailPage(postId: postId)),
      );
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
  Future<void> handleIncomingNotification(SocialNotificationModel note) async {
    String title = '';
    String body = '';
    String largeIconPath = '';

    // 1. 根据类型定制文本
    if (note.type == 'LIKE') {
      title = '🔥 有人点赞了你';
      body = '${note.triggerName} 赞了你的帖子: "${note.postTitle}"';
    } else if (note.type == 'COMMENT') {
      title = '💬 收到新评论';
      body = '${note.triggerName}: "${note.commentContent ?? ''}"';
    }

    // 2. 准备大图标 (用户头像)
    final String? avatarPath = await _downloadAndSaveFile(
      note.triggerAvatar,
      'avatar_${note.triggerId}.png',
    );

    // 3. 配置 Android 样式
    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'social_alerts',
          '社交动态',
          channelDescription: '点赞、评论等社交通知',
          importance: Importance.max,
          priority: Priority.high,
          showWhen: true,
          color: Colors.blueAccent, // 通知的小图标颜色
          largeIcon: avatarPath != null
              ? FilePathAndroidBitmap(avatarPath)
              : null,
          // 使用 BigTextStyle 支持长文本展示
          styleInformation: BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: note.type == 'LIKE' ? '新增点赞' : '新增评论',
          ),
          // 允许点击通知清除
          ticker: 'ticker',
        );

    // 4. 配置 iOS 样式
    final DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      attachments: avatarPath != null
          ? [DarwinNotificationAttachment(avatarPath)]
          : null,
      subtitle: note.postTitle,
    );

    final NotificationDetails platformDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    // 5. 显示通知
    await _notificationsPlugin.show(
      note.hashCode, // 确保 ID 唯一，防止覆盖
      title,
      body,
      platformDetails,
      payload: jsonEncode({'postId': note.postId}),
    );
  }
}
