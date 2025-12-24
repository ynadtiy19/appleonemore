import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_quill/quill_delta.dart';

import '../services/api_service.dart'; // 确保路径正确

/// Quill 富文本翻译服务
class QuillTranslationService {
  static final QuillTranslationService _instance =
      QuillTranslationService._internal();
  factory QuillTranslationService() => _instance;
  QuillTranslationService._internal();

  static final RegExp _anchorRegex = RegExp(
    r'\[([\s\S]*?)\]\s*\(id\s*:\s*(\d+)(:[\w]+)?\s*\)',
    multiLine: true,
  );

  /// 执行翻译
  Future<Delta> translateDelta(Delta originalDelta, String targetLang) async {
    try {
      if (originalDelta.isEmpty) return Delta();

      // 1. 编码
      final encodingResult = _encode(originalDelta);
      final String textToTranslate = encodingResult.payload;

      if (textToTranslate.trim().isEmpty) {
        return originalDelta;
      }

      // 2. 准备 System Prompt
      const String systemPrompt =
          "Role: Translator. "
          "Task: Translate the text inside the Markdown brackets `[...]` into the target language. "
          "CRITICAL RULES: "
          "1. KEEP the Link ID `(id:N)` EXACTLY as is. "
          "2. Do NOT nest links. "
          "3. Translate only the text content inside `[]`."
          "4. Keep formatting symbols intact.";

      // 3. 调用 API (System Prompt 单独传递)
      final result = await ApiService.translate(
        textToTranslate,
        targetLang,
        system: systemPrompt, // 这里传入 system 参数
      );

      if (result == null || result.text.isEmpty) {
        throw Exception("Translation API returned empty response");
      }

      // 4. 解码
      final Delta translatedDelta = _decode(originalDelta, result.text);
      return translatedDelta;
    } catch (e) {
      debugPrint("QuillTranslationService Error: $e");
      return originalDelta;
    }
  }

  /// 编码：提取文本并标记 ID
  ({String payload, int count}) _encode(Delta delta) {
    final StringBuffer buffer = StringBuffer();
    int count = 0;
    final List<Operation> ops = delta.toList();

    for (int i = 0; i < ops.length; i++) {
      final op = ops[i];

      // 修复核心点：将 data 赋值给局部变量以启用类型提升
      final data = op.data;
      final attrs = op.attributes;

      // === Case A: 纯文本 ===
      if (data is String) {
        if (data == '\n') continue;

        if (data.trim().isNotEmpty) {
          final escapedText = _escapeSpecialChars(data);
          buffer.write('[$escapedText](id:$i)');
          count++;
        }
      }
      // === Case B: 图片/Embed 且包含 alt 属性 ===
      else if (data is Map && attrs != null && attrs.containsKey('alt')) {
        final altText = attrs['alt'];
        if (altText is String && altText.isNotEmpty) {
          final escapedAlt = _escapeSpecialChars(altText);
          buffer.write('[$escapedAlt](id:$i:alt)');
          count++;
        }
      }
    }

    return (payload: buffer.toString(), count: count);
  }

  /// 解码：解析字符串并回填到 Delta 副本
  Delta _decode(Delta originalDelta, String translatedText) {
    // 1. 深拷贝原始 Delta
    final List<dynamic> jsonList = jsonDecode(
      jsonEncode(originalDelta.toJson()),
    );
    final Delta newDelta = Delta.fromJson(jsonList);

    // 获取 ops 列表
    final List<Operation> newOps = newDelta.toList();

    // 2. 正则匹配并回填
    final Iterable<RegExpMatch> matches = _anchorRegex.allMatches(
      translatedText,
    );

    for (final match in matches) {
      String content = match.group(1) ?? "";
      final String indexStr = match.group(2) ?? "-1";
      final int index = int.tryParse(indexStr) ?? -1;
      final String? subType = match.group(3);

      if (index < 0 || index >= newOps.length) continue;

      content = _unescapeSpecialChars(content);

      if (subType == null || subType.isEmpty) {
        // --- 普通文本替换 ---
        final originalOp = newOps[index];
        final originalData = originalOp.data; // 局部变量类型提升

        if (originalData is String) {
          // 修复核心点：使用 Operation.insert 替代 Operation() 原始构造函数
          // Operation.insert(data, attributes) 会自动处理 key 和 length
          newOps[index] = Operation.insert(content, originalOp.attributes);
        }
      } else if (subType == ':alt') {
        // --- Alt 属性替换 ---
        final originalOp = newOps[index];
        final originalData = originalOp.data; // 局部变量类型提升

        if (originalData is Map) {
          final Map<String, dynamic> newAttrs = Map<String, dynamic>.from(
            originalOp.attributes ?? {},
          );
          newAttrs['alt'] = content;

          // 修复核心点：Embed 对象也使用 Operation.insert
          newOps[index] = Operation.insert(
            originalData, // 这里传入的是 Map (Embed 对象)
            newAttrs,
          );
        }
      }
    }

    return Delta.fromOperations(newOps);
  }

  String _escapeSpecialChars(String input) {
    return input.replaceAll('[', '&#91;').replaceAll(']', '&#93;');
  }

  String _unescapeSpecialChars(String input) {
    return input.replaceAll('&#91;', '[').replaceAll('&#93;', ']');
  }
}
