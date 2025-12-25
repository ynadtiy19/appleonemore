class AiRequestModel {
  final String requestId; // 按照您的要求，这里将传入 userId
  final String text;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final List<Map<String, dynamic>> history; // 历史聊天记录
  final String? userApiKey; // 预留字段：用户自定义 Key

  AiRequestModel({
    required this.requestId,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    this.history = const [],
    this.userApiKey,
  });

  Map<String, dynamic> toJson() {
    return {
      "requestId": requestId,
      "text": text,
      "senderId": senderId,
      "senderName": senderName,
      "senderAvatar": senderAvatar,
      "history": history,
      if (userApiKey != null) "apiKey": userApiKey,
    };
  }
}

/// 用于解析后端返回的 AI 响应
class AiResponseModel {
  final String requestId;
  final String originalText;
  final String responseText;
  final String timestamp;

  AiResponseModel({
    required this.requestId,
    required this.originalText,
    required this.responseText,
    required this.timestamp,
  });

  factory AiResponseModel.fromMap(Map<String, dynamic> map) {
    return AiResponseModel(
      requestId: map['requestId']?.toString() ?? '',
      originalText: map['originalText']?.toString() ?? '',
      responseText: map['responseText']?.toString() ?? '',
      timestamp: map['timestamp']?.toString() ?? '',
    );
  }
}
