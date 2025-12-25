import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'voice_chat_widget.dart';

class SesameChatPage extends StatefulWidget {
  const SesameChatPage({super.key});

  @override
  State<SesameChatPage> createState() => _SesameChatPageState();
}

class _SesameChatPageState extends State<SesameChatPage> {
  late Future<String> _tokenFuture;

  @override
  void initState() {
    super.initState();
    // 初始化时开始获取 Token
    _tokenFuture = fetchIdToken();
  }

  /// 重新获取 Token (用于错误重试)
  void _retryFetch() {
    setState(() {
      _tokenFuture = fetchIdToken();
    });
  }

  /// 你提供的 API 请求逻辑
  Future<String> fetchIdToken() async {
    final url = Uri.parse("https://mydiumtify.globeapp.dev/sesameai");

    try {
      final response = await http.post(url);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        final token = data["id_token"];
        if (token != null && token.toString().isNotEmpty) {
          return token;
        } else {
          throw Exception("Token 为空");
        }
      } else {
        throw Exception("请求失败，状态码: ${response.statusCode}");
      }
    } catch (e) {
      throw Exception("请求 id_token 出错: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 使用白色背景，配合 VoiceChatWidget 的设计风格
      backgroundColor: Colors.white,
      body: SafeArea(
        child: FutureBuilder<String>(
          future: _tokenFuture,
          builder: (context, snapshot) {
            // 1. 加载中
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF5A6230)),
                    SizedBox(height: 16),
                    Text(
                      "Securing connection...",
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            // 2. 出错
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Initialization Failed",
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${snapshot.error}",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _retryFetch,
                        icon: const Icon(Icons.refresh),
                        label: const Text("Retry"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF5A6230),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            // 3. 成功 -> 显示通话组件
            final token = snapshot.data!;

            return VoiceChatWidget(
              token: token,
              // 这里的名字必须对应 Android 原生 assets 里的文件名
              // 例如 assets/kira_en.wav -> contactName: 'Kira-EN'
              contactName: 'Kira-EN',
              characterName: 'Kira',
              onCallEnded: () {
                // 通话结束时的处理，通常是退出页面
                if (mounted && Navigator.canPop(context)) {
                  Navigator.pop(context);
                } else {
                  // 如果是根页面，也许你想重置状态？
                  _retryFetch();
                  debugPrint("Call ended, staying on page.");
                }
              },
            );
          },
        ),
      ),
    );
  }
}
