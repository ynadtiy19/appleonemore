import 'dart:convert';

import 'package:http/http.dart' as http;

class PaymentService {
  static const String baseUrl = 'https://appleonemorechatwithu.globeapp.dev';

  /// 1. 创建订单
  /// 返回后端给出的支付链接信息 (JSON Map)
  Future<Map<String, dynamic>> createOrder({
    required String type,
    required String outTradeNo,
    required String name,
    required String money,
    required String device,
  }) async {
    final url = Uri.parse('$baseUrl/submit');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'type': type,
          'out_trade_no': outTradeNo,
          'name': name,
          'money': money,
          'device': device,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // code = 1 表示成功拿到支付链接
        if (data['code'] == 1) {
          return data;
        } else {
          throw Exception(data['msg'] ?? '获取支付链接失败');
        }
      } else {
        throw Exception('服务器错误: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('网络请求异常: $e');
    }
  }

  /// 2. 查询订单状态
  /// 返回 true 表示支付成功，false 表示未支付或支付失败
  Future<bool> checkOrderStatus(String outTradeNo) async {
    final url = Uri.parse('$baseUrl/query?out_trade_no=$outTradeNo');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // 根据文档：status 1 为支付成功，0 为未支付
        if (data['code'] == 1 && data['status'] == 1) {
          return true;
        }
      }
      return false;
    } catch (e) {
      print('查询出错: $e');
      return false;
    }
  }
}
