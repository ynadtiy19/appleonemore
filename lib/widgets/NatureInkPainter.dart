import 'dart:math';

import 'package:flutter/material.dart';

class NatureInkPainter extends CustomPainter {
  final double animationValue;
  NatureInkPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 50);

    final center = Offset(size.width * 0.5, size.height * 0.4);

    // 绘制三层类似水墨晕染的圆形，随动画震荡
    for (int i = 0; i < 3; i++) {
      final opacity = (0.08 - (i * 0.02)) * (1.0 - animationValue * 0.5);
      paint.color = const Color(0xFF4A6CF7).withOpacity(opacity.clamp(0, 1));

      final radius =
          (size.width * 0.3) +
          (i * 40) +
          (sin(animationValue * pi * 2 + i) * 20);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant NatureInkPainter oldDelegate) => true;
}
