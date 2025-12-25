import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/payment_service.dart';

class PaymentPage extends StatefulWidget {
  const PaymentPage({super.key});

  @override
  State<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends State<PaymentPage> {
  final PaymentService _paymentService = PaymentService();

  // 表单状态 Key，用于验证输入
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // 金额输入控制器
  final TextEditingController _amountController = TextEditingController(
    text: "1.00",
  );

  // 状态管理变量
  bool _isLoading = false; // 是否正在请求支付链接
  bool _isPolling = false; // 是否正在轮询查询结果
  String _statusText = "等待支付"; // 界面显示的文字
  Timer? _pollingTimer; // 轮询定时器

  // 选中的支付方式，默认为支付宝
  String _selectedPaymentType = "alipay";

  @override
  void dispose() {
    _stopPolling();
    _amountController.dispose();
    super.dispose();
  }

  // 停止轮询
  void _stopPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = null;
    if (mounted) {
      setState(() {
        _isPolling = false;
      });
    }
  }

  // 开始支付主流程
  Future<void> _startPayment() async {
    // 1. 验证表单（金额是否合法）
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 收起键盘
    FocusScope.of(context).unfocus();

    setState(() {
      _isLoading = true;
      _statusText = "正在创建订单...";
    });

    // 2. 准备数据
    // 生成唯一订单号
    final String tradeNo = "ORDER_${DateTime.now().millisecondsSinceEpoch}";

    // 格式化金额，保留两位小数
    final double amountVal = double.parse(_amountController.text);
    final String moneyStr = amountVal.toStringAsFixed(2);

    try {
      // 3. 请求后端获取支付链接
      final result = await _paymentService.createOrder(
        type: _selectedPaymentType, // 动态使用选中的支付方式
        outTradeNo: tradeNo,
        name: "测试VIP充值", // 商品名称
        money: moneyStr, // 动态使用输入的金额
        device: "mobile",
      );

      // 4. 解析跳转链接
      // 易支付返回的字段可能是 payurl, qrcode, 或 urlscheme
      String? jumpUrl =
          result['payurl'] ?? result['qrcode'] ?? result['urlscheme'];

      if (jumpUrl != null && jumpUrl.isNotEmpty) {
        setState(() {
          _isLoading = false;
          _statusText = "正在跳转支付...";
        });

        // 5. 打开外部浏览器/支付APP
        await _launchPaymentUrl(jumpUrl);

        // 6. 开始轮询查询结果
        _startPollingOrder(tradeNo);
      } else {
        throw Exception("未获取到有效的支付跳转链接");
      }
    } catch (e) {
      _stopPolling();
      setState(() {
        _isLoading = false;
        _statusText = "支付发起失败";
      });
      _showSnackBar("错误: $e", Colors.red);
    }
  }

  // 唤起外部应用
  Future<void> _launchPaymentUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      // 部分模拟器可能无法处理 intent scheme，真机通常没问题
      throw Exception('无法打开支付链接: $url');
    }
  }

  // 轮询查单逻辑
  void _startPollingOrder(String outTradeNo) {
    setState(() {
      _isPolling = true;
      _statusText = "支付中，正在查询结果...";
    });

    // 每 3 秒查询一次
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      print("正在查询订单: $outTradeNo");
      final isSuccess = await _paymentService.checkOrderStatus(outTradeNo);

      if (isSuccess) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _isPolling = false;
            _statusText = "支付成功！感谢您的支持。";
          });
          _showSuccessDialog();
        }
      }
    });
  }

  // 弹窗提示成功
  void _showSuccessDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("支付成功"),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 60),
            SizedBox(height: 10),
            Text("订单已完成支付"),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // 这里可以做一些后续操作，比如跳转回首页或刷新余额
            },
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("收银台"),
        backgroundColor: Colors.blueAccent,
        foregroundColor: Colors.white,
      ),
      // 使用 SingleChildScrollView 防止键盘弹出时溢出
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 商品与金额输入卡片
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.shopping_bag_outlined,
                        size: 40,
                        color: Colors.orange,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "测试VIP充值",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // 金额输入框
                      TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: "充值金额",
                          prefixText: "¥ ",
                          border: OutlineInputBorder(),
                          helperText: "输入范围: 1.00 ~ 5000.00",
                        ),
                        style: const TextStyle(
                          fontSize: 24,
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                        // 输入验证逻辑
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return '请输入金额';
                          }
                          final double? amount = double.tryParse(value);
                          if (amount == null) {
                            return '请输入有效的数字';
                          }
                          if (amount < 1.00) {
                            return '最低充值 1.00 元';
                          }
                          if (amount > 5000.00) {
                            return '最高充值 5000.00 元';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // 支付方式选择标题
              const Text(
                "选择支付方式",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              // 支付方式列表
              Card(
                elevation: 2,
                child: Column(
                  children: [
                    // 支付宝选项
                    RadioListTile<String>(
                      value: "alipay",
                      groupValue: _selectedPaymentType,
                      title: const Text("支付宝"),
                      subtitle: const Text("推荐支付宝用户使用"),
                      secondary: const Icon(Icons.payment, color: Colors.blue),
                      activeColor: Colors.blue,
                      onChanged: (value) {
                        setState(() {
                          _selectedPaymentType = value!;
                        });
                      },
                    ),
                    const Divider(height: 1),
                    // 微信支付选项
                    RadioListTile<String>(
                      value: "wxpay",
                      groupValue: _selectedPaymentType,
                      title: const Text("微信支付"),
                      subtitle: const Text("推荐微信用户使用"),
                      secondary: const Icon(
                        Icons.chat_bubble,
                        color: Colors.green,
                      ),
                      activeColor: Colors.green,
                      onChanged: (value) {
                        setState(() {
                          _selectedPaymentType = value!;
                        });
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // 状态显示
              if (_isLoading || _isPolling) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 10),
              ],
              Center(
                child: Text(
                  _statusText,
                  style: TextStyle(
                    fontSize: 16,
                    color: _statusText.contains("成功")
                        ? Colors.green
                        : Colors.grey[700],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(height: 20),

              // 支付按钮
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: (_isLoading || _isPolling) ? null : _startPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedPaymentType == 'wxpay'
                        ? Colors.green
                        : Colors.blueAccent,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    "立即支付 (${_selectedPaymentType == 'alipay' ? '支付宝' : '微信'})",
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),

              // 取消查询按钮
              if (_isPolling)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextButton(
                    onPressed: _stopPolling,
                    child: const Text("已完成支付或取消查询"),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
