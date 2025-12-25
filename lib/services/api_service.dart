import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/sticker_model.dart';
import '../models/translation_model.dart';
import '../utils/constants.dart';

class ApiService {
  /// 📋 复制文本到剪切板
  static Future<void> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// 🖼 下载图片并复制
  /// - Android: 复制图片文件
  /// - 其他平台: 复制图片 URL（兜底）
  static Future<void> copyImageFromUrl(String imageUrl) async {
    try {
      // Web / iOS 兜底
      if (kIsWeb || Platform.isIOS) {
        await Clipboard.setData(ClipboardData(text: imageUrl));
        return;
      }

      // Android / Desktop
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Download image failed');
      }

      final Uint8List bytes = response.bodyBytes;

      final tempDir = await getTemporaryDirectory();
      final file = File(
        '${tempDir.path}/copied_image_${DateTime.now().millisecondsSinceEpoch}.png',
      );

      await file.writeAsBytes(bytes);

      // Flutter 没有直接复制 File 的 API
      // 这里采用：复制 file path（Android 可被系统识别）
      await Clipboard.setData(ClipboardData(text: file.path));
    } catch (e) {
      debugPrint('Copy image error: $e');
      // 最差兜底：复制 URL
      await Clipboard.setData(ClipboardData(text: imageUrl));
    }
  }

  static Future<String?> uploadImage(File imageFile) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(Constants.cloudinaryUrl),
      );
      request.fields['upload_preset'] = Constants.cloudinaryPreset;
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );
      var response = await request.send();
      if (response.statusCode == 200) {
        final respStr = await response.stream.bytesToString();
        return jsonDecode(respStr)['secure_url'];
      }
      return null;
    } catch (e) {
      debugPrint("Upload Error: $e");
      return null;
    }
  }

  static Future<List<StickerItem>> fetchStickers() async {
    try {
      final response = await http.get(
        Uri.parse('https://stickers-in.cc-cluster-2.io/v1/fetch'),
        headers: Constants.translationHeaders, // 统一使用翻译的请求头
      );

      if (response.statusCode == 200) {
        // 使用 utf8.decode 防止中文乱码
        final String decodedBody = utf8.decode(response.bodyBytes);
        final Map<String, dynamic> jsonResponse = jsonDecode(decodedBody);

        final stickerResponse = StickerResponse.fromJson(jsonResponse);

        // 返回按 stickerSetOrder 和 stickerOrder 排序后的列表，方便 UI 渲染
        List<StickerItem> list = stickerResponse.data.defaultStickers;
        list.sort((a, b) {
          int setCmp = a.stickerSetOrder.compareTo(b.stickerSetOrder);
          if (setCmp != 0) return setCmp;
          return a.stickerOrder.compareTo(b.stickerOrder);
        });

        return list;
      } else {
        print("Fetch Stickers Error: ${response.statusCode}");
        return [];
      }
    } catch (e) {
      print("Fetch Stickers Exception: $e");
      return [];
    }
  }

  static Future<TranslationResult?> translate(
    String text,
    String targetLang, {
    String? system,
  }) async {
    if (text.trim().isEmpty) return null;

    try {
      // 请确保 Constants 类已定义
      var request = http.Request('POST', Uri.parse(Constants.translationUrl));
      request.headers.addAll(Constants.translationHeaders);

      final bodyData = {
        "msgId": DateTime.now().millisecondsSinceEpoch.toString(),
        "text": text,
        "languages": [targetLang],
        // 如果 system 不为空，则加入请求体
        if (system != null) "system": system,
      };

      request.body = jsonEncode(bodyData);
      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        final json = jsonDecode(responseBody);

        // 建议加上空安全检查
        if (json['data'] != null && json['data']['translations'] != null) {
          final translations = json['data']['translations'] as List;

          if (translations.isNotEmpty) {
            final t = translations.first;
            return TranslationResult(
              language: t['language_translated'] ?? targetLang,
              text: t['message_translated'] ?? text,
            );
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint("Translate Error: $e");
      return null;
    }
  }

  /// 🎞️ 获取 Intercom GIFs
  /// 返回 URL 列表
  static Future<List<String>> fetchIntercomGifs({String query = ''}) async {
    try {
      var headers = {
        'Accept': ' */*',
        'Content-Type': 'application/x-www-form-urlencoded',
        'Origin': ' https://www.elegantthemes.com',
        'User-Agent':
            ' Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 Edg/144.0.0.0',
        'Cache-Control': ' no-cache',
        'Pragma': ' no-cache',
      };

      var request = http.Request(
        'POST',
        Uri.parse('https://api-iam.intercom.io/messenger/web/gifs'),
      );

      request.bodyFields = {
        'app_id': 'hrpt54hy',
        'v': '3',
        'g': '5839509c7ebc3d18eebb2635b5383d33bd89d98f',
        's': '1ab367b2-343a-4efa-b458-03f45cae95e2',
        'r': 'https://www.elegantthemes.com/',
        'platform': 'web',
        'installation_type': 'js-snippet',
        'installation_version': 'undefined',
        'Idempotency-Key': '1fb41c34ab9cdd74',
        'internal': '',
        'is_intersection_booted': 'false',
        'page_title': '加入优雅主题',
        'user_active_company_id': '-1',
        'user_data': '{"anonymous_id":"80109712-c126-4c90-a265-c09853d7450c"}',
        'query': query, // 动态关键词
        'referer': 'https://www.elegantthemes.com/join/',
        'device_identifier': 'b015be9f-e920-47c8-829e-9d2cc6443e5a',
      };

      request.headers.addAll(headers);

      http.StreamedResponse response = await request.send();

      if (response.statusCode == 200) {
        String responseStr = await response.stream.bytesToString();
        final json = jsonDecode(responseStr);

        if (json['results'] != null) {
          final results = json['results'] as List;
          // 提取 GIF 的 URL
          // results 包含 "url" (全尺寸) 和 "previewUrl" (预览)
          // 这里返回全尺寸 URL 用于插入，或者你可以自定义返回模型
          return results.map<String>((e) => e['url'].toString()).toList();
        }
      } else {
        debugPrint(response.reasonPhrase);
      }
      return [];
    } catch (e) {
      debugPrint("Fetch GIF Error: $e");
      return [];
    }
  }
}
