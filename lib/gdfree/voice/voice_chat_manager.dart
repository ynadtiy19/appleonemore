import 'dart:async';

import 'package:flutter/services.dart';

class VoiceChatManager {
  static const MethodChannel _methodChannel = MethodChannel(
    'com.sesame.voicechat/methods',
  );
  static const EventChannel _eventChannel = EventChannel(
    'com.sesame.voicechat/recordStream',
  );

  StreamSubscription? _subscription;

  // 回调函数
  Function(String status)? onConnectionChanged;
  Function(Uint8List data, bool hasVoice)? onAudioData; // 用于绘制波形
  Function(String error)? onError;

  /// 连接 Session (Native处理 WebSocket & Audio)
  Future<bool> connect(String idToken) async {
    try {
      _listenToNativeEvents();
      // 调用 Kotlin 的 connect 方法
      final bool success = await _methodChannel.invokeMethod('connect', {
        'idToken': idToken,
      });
      return success;
    } catch (e) {
      print("Native Connect Error: $e");
      onError?.call(e.toString());
      return false;
    }
  }

  /// 断开连接
  Future<void> disconnect() async {
    try {
      await _methodChannel.invokeMethod('disconnect');
      _subscription?.cancel();
    } catch (e) {
      print("Native Disconnect Error: $e");
    }
  }

  /// 设置静音
  Future<void> setMute(bool isMuted) async {
    try {
      await _methodChannel.invokeMethod('setMute', {'isMuted': isMuted});
    } catch (e) {
      print("Native Mute Error: $e");
    }
  }

  /// 监听原生发来的事件 (状态变更 + 音频波形数据)
  void _listenToNativeEvents() {
    _subscription?.cancel();
    _subscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is Map) {
          // 1. 处理连接状态
          if (event.containsKey('type') && event['type'] == 'status') {
            final status = event['value'] as String;
            onConnectionChanged?.call(status);
          }
          // 2. 处理错误信息
          else if (event.containsKey('type') && event['type'] == 'error') {
            onError?.call(event['value'].toString());
          }
          // 3. 处理音频数据 (用于 UI 动画)
          else if (event.containsKey('data')) {
            final data = event['data'] as Uint8List;
            final hasVoice = event['hasVoice'] as bool? ?? false;
            onAudioData?.call(data, hasVoice);
          }
        }
      },
      onError: (error) {
        print("EventChannel Error: $error");
        onError?.call(error.toString());
      },
    );
  }

  void dispose() {
    disconnect();
  }
}
