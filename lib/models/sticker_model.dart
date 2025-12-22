class StickerResponse {
  final StickerData data;

  StickerResponse({required this.data});

  factory StickerResponse.fromJson(Map<String, dynamic> json) {
    return StickerResponse(data: StickerData.fromJson(json['data'] ?? {}));
  }
}

class StickerData {
  final List<StickerItem> defaultStickers;

  StickerData({required this.defaultStickers});

  factory StickerData.fromJson(Map<String, dynamic> json) {
    var list = json['defaultStickers'] as List? ?? [];
    List<StickerItem> stickers = list
        .map((e) => StickerItem.fromJson(e))
        .toList();
    return StickerData(defaultStickers: stickers);
  }
}

class StickerItem {
  final String stickerName;
  final int stickerOrder;
  final String stickerSetId;
  final String stickerSetName;
  final int stickerSetOrder;
  final String stickerUrl;
  final String id;
  final bool enableFlag;

  StickerItem({
    required this.stickerName,
    required this.stickerOrder,
    required this.stickerSetId,
    required this.stickerSetName,
    required this.stickerSetOrder,
    required this.stickerUrl,
    required this.id,
    required this.enableFlag,
  });

  factory StickerItem.fromJson(Map<String, dynamic> json) {
    return StickerItem(
      stickerName: json['stickerName'] ?? "",
      // 处理某些 API 返回的是 String 类型的数字
      stickerOrder: _toInt(json['stickerOrder']),
      stickerSetId: json['stickerSetId'] ?? "",
      stickerSetName: json['stickerSetName'] ?? "",
      stickerSetOrder: _toInt(json['stickerSetOrder']),
      stickerUrl: json['stickerUrl'] ?? "",
      id: json['id'] ?? "",
      enableFlag: json['enableFlag'] ?? false,
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, dynamic> toJson() => {
    'stickerName': stickerName,
    'stickerOrder': stickerOrder.toString(),
    'stickerSetId': stickerSetId,
    'stickerSetName': stickerSetName,
    'stickerSetOrder': stickerSetOrder.toString(),
    'stickerUrl': stickerUrl,
    'id': id,
    'enableFlag': enableFlag,
  };
}
