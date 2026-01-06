import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../models/chat_msg_model.dart';

class ThirdPartyAiService extends GetxService {
  static const String _apiUrl =
      'https://appleonemorechatwithu.globeapp.dev/chatwithgemini';

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
  };

  Future<String?> fetchReply({
    required String currentInput,
    required List<ChatMsgModel> history,
    String botName = "Gemini",
  }) async {
    try {
      print("📤 [AI Service] 正在请求新后端: $_apiUrl");

      final List<Map<String, dynamic>> historyPayload = history.map((msg) {
        return {
          "type": msg.type,
          "content": msg.content, // 后端读取的是 content
          "senderName": msg.senderName, // 后端读取的是 senderName
        };
      }).toList();

      final body = json.encode({
        "currentInput": currentInput,
        "botName": botName,
        "history": historyPayload,
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
        print("❌ 访问api错误: ${response.statusCode} - ${response.reasonPhrase}");
        print("❌ 返回体错误: ${response.body}");
        return null;
      }
    } catch (e) {
      print("❌ 额外错误: $e");
      return null;
    }
  }
}
