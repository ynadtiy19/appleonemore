import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';

class DividerBlockEmbed extends CustomBlockEmbed {
  static const String embedType = 'divider';

  const DividerBlockEmbed() : super(embedType, 'hr');
}

class DividerEmbedBuilder extends EmbedBuilder {
  @override
  String get key => DividerBlockEmbed.embedType;

  @override
  bool get expanded => false;

  @override
  Widget build(BuildContext context, EmbedContext embedContext) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 30.0),
      child: CustomDividerWidget(),
    );
  }
}

class CustomDividerWidget extends StatelessWidget {
  const CustomDividerWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      width: double.infinity,
      child: CustomPaint(painter: _DividerPainter()),
    );
  }
}

// 4. 核心绘制逻辑 (🎨 重新设计样式)
class _DividerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final double cx = size.width / 2;
    final double cy = size.height / 2;

    final Paint centerDotPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;

    final Paint sideDotPaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;
    final Paint linePaint = Paint()
      ..color = Colors.black54
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    const double centerRadius = 3.5; // 中心点变大
    const double sideRadius = 2.0; // 侧边点保持小巧
    const double dotSpacing = 18.0; // 点之间的间距
    const double lineGap = 16.0; // 线条距离点的间距

    const double margin = 50.0;

    canvas.drawCircle(Offset(cx, cy), centerRadius, centerDotPaint);

    canvas.drawCircle(Offset(cx - dotSpacing, cy), sideRadius, sideDotPaint);
    canvas.drawCircle(Offset(cx + dotSpacing, cy), sideRadius, sideDotPaint);

    final double leftLineEndX = cx - dotSpacing - lineGap;
    final double rightLineStartX = cx + dotSpacing + lineGap;

    canvas.drawLine(Offset(margin, cy), Offset(leftLineEndX, cy), linePaint);

    canvas.drawLine(
      Offset(rightLineStartX, cy),
      Offset(size.width - margin, cy),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
