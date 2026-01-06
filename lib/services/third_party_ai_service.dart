import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../models/chat_msg_model.dart';

class ThirdPartyAiService extends GetxService {
  static const String _apiUrl =
      'https://nucleo-ai-0bddb5430bd2.herokuapp.com/chat';

  static const Map<String, String> _headers = {
    'cookie':
        'show_donation=true; session=.eJzVjssKwjAURH9FsrZvG9uCoFgFxQeiKK5KiDFNbZvS5vpA_XdT_AKXri4zzMy5T8QKInIUoXMOiknKSAnwGPLWNaksUBeVpGA6cGGdTGhZCaqgbp1UqaqJLCtPPZNLyXMGDaupLBUrVVu2iDUa80DSmb2dQL2wl7Nrf-Otq9uZHnqjzE9E6MTHzIf9ypjvpjGkWXVvNnzQhNigGtYOouj5B18m4qRhX4AhCajUfTkODrywH-DA9f0Q2_o4GL1_LnwA-fmKAg.aVvtkA.Sy2stBFp7TAWua93z8drYnArrPw',
    'Content-Type': 'application/json',
  };

  static const String divider =
      '_____________________________________________________________________________________________________________________________________________';

  Future<String?> fetchReply({
    required String currentInput,
    required List<ChatMsgModel> history,
    String botName = "Gemini",
  }) async {
    try {
      final prompt = _buildPrompt(currentInput, history, botName);

      print("📤 [AI Service] 正在发送的 Prompt:\n$prompt");

      final body = json.encode({
        "message": prompt,
        "speed_research": false,
        "deep_reasoning": false,
        "slash_command": null,
      });

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: _headers,
        body: body,
      );

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(utf8.decode(response.bodyBytes));
        return jsonResponse['response']?.toString();
      } else {
        print("❌ AI API Error: ${response.reasonPhrase}");
        return null;
      }
    } catch (e) {
      print("❌ AI Exception: $e");
      return null;
    }
  }

  /// 核心修改：只提取 msg.content
  String _buildPrompt(
    String currentInput,
    List<ChatMsgModel> history,
    String botName,
  ) {
    final buffer = StringBuffer();

    // 1. 拼装当前问题
    buffer.writeln(currentInput);
    buffer.writeln(divider);
    buffer.writeln("CONTEXT");
    buffer.writeln(divider);

    // 2. 处理历史记录
    // 逻辑：
    // a. 过滤掉非文本消息 (Type != 1)
    // b. 过滤掉重复的当前输入
    // c. 取最近 15 条
    // d. 反转顺序 (按时间从旧到新)
    final validHistory = history
        .where((m) => m.type == 1) // 只要文本，不要图片链接
        .where((m) => m.content.trim().isNotEmpty) // 不要空消息
        .where((m) => m.content != currentInput) // 避免把当前问题重复放进历史
        .take(15)
        .toList()
        .reversed;

    for (final msg in validHistory) {
      String cleanContent = msg.content.trim();

      // 过滤掉包含 http 的长链接（防止 AI 去分析 APK 或图片 URL）
      if (cleanContent.startsWith("http") || cleanContent.length > 500) {
        continue;
      }

      String roleLabel;
      if (msg.senderName == botName) {
        roleLabel = "assistant";
      } else {
        // 保留用户名以便 AI 知道是谁在说话，例如 "User(Tom)"
        roleLabel = "User(${msg.senderName})";
      }
      buffer.writeln("$roleLabel: $cleanContent");
      buffer.writeln();
    }

    return buffer.toString().trim();
  }
}
