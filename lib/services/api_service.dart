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
    String targetLang,
  ) async {
    if (text.trim().isEmpty) return null;

    try {
      var request = http.Request('POST', Uri.parse(Constants.translationUrl));
      request.headers.addAll(Constants.translationHeaders);

      final bodyData = {
        "msgId": DateTime.now().millisecondsSinceEpoch.toString(),
        "text": text,
        // 这里只传用户选中的那一个语言代码
        "languages": [targetLang],
      };

      request.body = jsonEncode(bodyData);
      final streamedResponse = await request.send();
      final responseBody = await streamedResponse.stream.bytesToString();

      if (streamedResponse.statusCode == 200) {
        final json = jsonDecode(responseBody);
        // 假设 API 返回结构是 data -> translations 数组
        final translations = json['data']['translations'] as List;

        if (translations.isNotEmpty) {
          final t = translations.first;
          return TranslationResult(
            language: t['language_translated'], // API 返回的语言代码
            text: t['message_translated'], // API 返回的翻译文本
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint("Translate Error: $e");
      return null;
    }
  }
}
