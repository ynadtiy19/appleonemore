import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';

/// 语音通话核心小部件
/// 功能：
/// 1. 待机状态显示 Lottie 动画，点击开始通话
/// 2. 通话状态显示波纹/RMS动画
/// 3. 处理与 Android 原生层的通信
class VoiceChatWidget extends StatefulWidget {
  /// 从后端获取到的 ID Token
  final String token;

  /// 联系人配置 (例如: 'Kira-EN', 'Hugo-FR')
  final String contactName;

  /// 角色名 (例如: 'Kira', 'Hugo')
  final String characterName;

  /// 当通话结束时回调
  final VoidCallback onCallEnded;

  const VoiceChatWidget({
    super.key,
    required this.token,
    this.contactName = 'Kira-EN',
    this.characterName = 'Kira',
    required this.onCallEnded,
  });

  @override
  State<VoiceChatWidget> createState() => _VoiceChatWidgetState();
}

class _VoiceChatWidgetState extends State<VoiceChatWidget>
    with SingleTickerProviderStateMixin {
  // --- Native Channels ---
  static const _methodChannel = MethodChannel('com.sesame.voicechat/control');
  static const _eventChannel = EventChannel('com.sesame.voicechat/events');

  // --- State ---
  String _statusText = "Tap sesame to start";
  bool _isConnected = false; // 是否已完全连接（Native层 WebSocket+Audio Ready）
  bool _isConnecting = false; // 是否正在连接中（UI Loading状态）
  bool _isMuted = false;
  bool _hasVoiceActivity = false; // 是否检测到说话

  StreamSubscription? _eventSubscription;

  // --- Animation ---
  late final Ticker _ticker;
  final Random _random = Random();
  double _expandValue = 0;
  double _ringWidthFactor = 0;
  int _ringWidthFactorDirection = 1;
  double _ringWidthFactorSpeed = 0.02;

  // 模拟音量震动
  double _visualRms = 0.0;

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _setupNativeListeners();
  }

  void _initAnimation() {
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      setState(() {
        // 1. 波纹扩散动画
        _expandValue += 0.012;
        if (_expandValue > 1) _expandValue = 0;

        // 2. 圆环宽度呼吸动画
        double randomFactor = _random.nextDouble() * 0.05;
        _ringWidthFactorSpeed = 0.02 + randomFactor * 0.5;
        _ringWidthFactor += _ringWidthFactorSpeed * _ringWidthFactorDirection;

        // 平滑缓动
        const easingFactor = 0.7;
        // 这里的计算仅用于 connected 状态下的背景圆环呼吸
        // ignore: unused_local_variable
        double smoothedFactor = sin(
          pow(_ringWidthFactor.clamp(0.0, 1.0), 1 / easingFactor) * (pi / 2),
        );

        if (_ringWidthFactor >= 1) {
          _ringWidthFactor = 1;
          _ringWidthFactorDirection = -1;
        } else if (_ringWidthFactor <= 0) {
          _ringWidthFactor = 0;
          _ringWidthFactorDirection = 1;
        }

        // 3. 模拟 RMS 音量震动逻辑
        // 如果检测到说话(voice_activity)，则大幅震动，否则微弱呼吸
        double targetRms = _hasVoiceActivity
            ? (0.3 + _random.nextDouble() * 0.4)
            : 0.05;
        // 线性插值平滑过渡
        _visualRms = _visualRms * 0.8 + targetRms * 0.2;
      });
    })..start();
  }

  void _setupNativeListeners() {
    // 监听原生事件
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      (event) {
        if (!mounted) return;
        final data = Map<String, dynamic>.from(event);
        final type = data['type'];
        final value = data['value'];

        switch (type) {
          case 'status':
            setState(() {
              if (value == "Connected" || value == "Ready") {
                _isConnected = true;
                _isConnecting = false;
                _statusText = "Connected";
              } else if (value == "Disconnected") {
                _isConnected = false;
                _isConnecting = false;
                _statusText = "Tap sesame to start";
              } else {
                // Connecting, Initializing, etc.
                _statusText = value.toString();
              }
            });
            break;
          case 'voice_activity':
            setState(() {
              _hasVoiceActivity = value == true;
            });
            break;
          case 'error':
            setState(() {
              _statusText = "Error: $value";
              _isConnecting = false;
              _isConnected = false;
            });
            break;
          case 'init_progress':
            setState(() => _statusText = "Cooking... $value%");
            break;
        }
      },
      onError: (error) {
        setState(() => _statusText = "Native Error: $error");
      },
    );
  }

  /// 点击 Lottie 触发连接
  Future<void> _startCall() async {
    if (_isConnecting || _isConnected) return;

    setState(() {
      _isConnecting = true;
      _statusText = "Requesting Permission...";
    });

    // 1. 请求权限
    var status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      setState(() {
        _statusText = "Microphone Permission Denied";
        _isConnecting = false;
      });
      return;
    }

    setState(() => _statusText = "Connecting...");

    // 2. 调用原生 connect 方法
    try {
      await _methodChannel.invokeMethod('connect', {
        'contactName': widget.contactName,
        'characterName': widget.characterName,
        'token': widget.token,
      });
      // 触觉反馈
      HapticFeedback.mediumImpact();
    } on PlatformException catch (e) {
      setState(() {
        _statusText = "Connection Failed: ${e.message}";
        _isConnecting = false;
      });
    }
  }

  Future<void> _toggleMute() async {
    try {
      final newMuteState = await _methodChannel.invokeMethod<bool>(
        'toggleMute',
      );
      setState(() {
        _isMuted = newMuteState ?? !_isMuted;
      });
      HapticFeedback.selectionClick();
    } catch (e) {
      debugPrint("Mute error: $e");
    }
  }

  Future<void> _disconnectAndClose() async {
    HapticFeedback.mediumImpact();
    setState(() {
      _statusText = "Disconnecting...";
    });

    try {
      await _methodChannel.invokeMethod('disconnect');
    } catch (e) {
      debugPrint("Disconnect error: $e");
    } finally {
      // 重置状态
      setState(() {
        _isConnected = false;
        _isConnecting = false;
        _statusText = "Tap sesame to start";
      });
      widget.onCallEnded();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _eventSubscription?.cancel();
    // 页面销毁时尝试断开连接
    _methodChannel.invokeMethod('disconnect').catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 顶部占位
        const Spacer(flex: 2),

        // --- 核心交互区域 (Lottie 或 波纹) ---
        SizedBox(
          width: 350,
          height: 350,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 1. 连接成功后：显示波纹动画
              if (_isConnected)
                CustomPaint(
                  size: const Size(350, 350),
                  painter: _WavePainter(
                    expandValue: _expandValue,
                    visualRms: _visualRms,
                    isConnected: _isConnected,
                  ),
                ),

              // 2. 未连接时：显示 Lottie 动画 (作为按钮)
              // 使用 AnimatedOpacity 实现淡入淡出切换
              AnimatedOpacity(
                opacity: _isConnected ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 500),
                child: IgnorePointer(
                  ignoring: _isConnected || _isConnecting, // 连接中或连接后不可点击
                  child: GestureDetector(
                    onTap: _startCall,
                    child: Lottie.asset(
                      'images/sesame.json',
                      width: 300,
                      height: 300,
                      fit: BoxFit.fill,
                      animate: !_isConnected, // 连接后停止动画节省资源
                    ),
                  ),
                ),
              ),

              // 3. 连接中：显示 Loading Indicator
              if (_isConnecting)
                const SizedBox(
                  width: 320,
                  height: 320,
                  child: CircularProgressIndicator(
                    color: Color(0xFF5A6230),
                    strokeWidth: 2,
                  ),
                ),

              // 4. 连接后中心图标 (可视化的麦克风状态)
              if (_isConnected)
                Icon(
                  _hasVoiceActivity ? Icons.graphic_eq : Icons.mic,
                  size: 48,
                  color: const Color(0xFF5A6230).withOpacity(0.8),
                ),
            ],
          ),
        ),

        const SizedBox(height: 40),

        // --- 状态文字 & 计时器 ---
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: Column(
            key: ValueKey(_statusText),
            children: [
              Text(
                _statusText,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                ),
              ),
              if (_isConnected) ...[
                const SizedBox(height: 10),
                const _TimerWidget(),
              ],
            ],
          ),
        ),

        const Spacer(flex: 1),

        // --- 底部控制栏 (仅在连接后显示) ---
        AnimatedOpacity(
          opacity: _isConnected ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 500),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 20,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 静音按钮
                _ControlButton(
                  icon: _isMuted ? Icons.mic_off : Icons.mic,
                  label: _isMuted ? "Unmute" : "Mute",
                  color: _isMuted ? Colors.orange : const Color(0xFF5A6230),
                  backgroundColor: _isMuted
                      ? Colors.orange.shade50
                      : const Color(0xFFF4F6EB),
                  onTap: _isConnected ? _toggleMute : null,
                ),

                // 挂断按钮
                _ControlButton(
                  icon: Icons.call_end,
                  label: "End Call",
                  color: Colors.white,
                  backgroundColor: Colors.red.shade400,
                  onTap: _isConnected ? _disconnectAndClose : null,
                  isLarge: true,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ==========================================
// 辅助组件 & 绘制器
// ==========================================

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color backgroundColor;
  final VoidCallback? onTap;
  final bool isLarge;

  const _ControlButton({
    Key? key,
    required this.icon,
    required this.label,
    required this.color,
    required this.backgroundColor,
    this.onTap,
    this.isLarge = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.all(isLarge ? 24 : 18),
            decoration: BoxDecoration(
              color: onTap == null ? Colors.grey.shade200 : backgroundColor,
              shape: BoxShape.circle,
              boxShadow: onTap != null
                  ? [
                      BoxShadow(
                        color: backgroundColor.withOpacity(0.4),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              color: onTap == null ? Colors.grey : color,
              size: isLarge ? 32 : 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: onTap == null ? Colors.grey : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimerWidget extends StatefulWidget {
  const _TimerWidget({Key? key}) : super(key: key);

  @override
  State<_TimerWidget> createState() => _TimerWidgetState();
}

class _TimerWidgetState extends State<_TimerWidget> {
  late final Timer _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final s = (_seconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F6EB),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        "$m:$s",
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Color(0xFF5A6230),
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final double expandValue; // 0.0 ~ 1.0 用于扩散波纹
  final double visualRms; // 0.0 ~ 1.0 用于模拟音量大小
  final bool isConnected;

  _WavePainter({
    required this.expandValue,
    required this.visualRms,
    required this.isConnected,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const baseRadius = 60.0;

    // 1. 绘制静态中心背景
    final centerPaint = Paint()
      ..color = isConnected ? const Color(0xFFC3CB9C) : Colors.transparent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, baseRadius, centerPaint);

    if (!isConnected) return;

    // 2. 绘制动态呼吸圆环 (受 visualRms 控制粗细)
    final ringPaint = Paint()
      ..color = const Color(0xFFE8F5E9).withOpacity(0.5)
      ..style = PaintingStyle.stroke;

    // 动态宽度计算
    final dynamicWidth = 20.0 + (visualRms * 60.0); // 最小20，最大80
    ringPaint.strokeWidth = dynamicWidth;

    // 绘制外圈光晕
    canvas.drawCircle(center, baseRadius + (dynamicWidth / 2), ringPaint);

    // 3. 绘制扩散波纹 (涟漪)
    final expandRadius = baseRadius + dynamicWidth + (expandValue * 80);
    final opacity = max(0.0, 1.0 - expandValue);

    final ripplePaint = Paint()
      ..color = const Color(0xFF5A6230).withOpacity(opacity * 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, expandRadius, ripplePaint);

    // 绘制第二层涟漪
    double secondExpand = expandValue - 0.5;
    if (secondExpand < 0) secondExpand += 1.0;

    final secondRadius = baseRadius + dynamicWidth + (secondExpand * 80);
    final secondOpacity = max(0.0, 1.0 - secondExpand);

    final secondRipplePaint = Paint()
      ..color = const Color(0xFF5A6230).withOpacity(secondOpacity * 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawCircle(center, secondRadius, secondRipplePaint);
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) => true;
}
