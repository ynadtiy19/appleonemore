import 'dart:math';

import 'package:flutter/material.dart';

double screenWidth(BuildContext context) => MediaQuery.of(context).size.width;

class RandomEmptyStateWidget extends StatefulWidget {
  const RandomEmptyStateWidget({super.key});

  @override
  State<RandomEmptyStateWidget> createState() => _RandomEmptyStateWidgetState();
}

class _RandomEmptyStateWidgetState extends State<RandomEmptyStateWidget> {
  late String _randomImagePath;

  @override
  void initState() {
    super.initState();
    final int randomIndex = Random().nextInt(5) + 1;
    _randomImagePath = 'images/$randomIndex.jpg';
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: screenWidth(context) / 2,
            height: screenWidth(context) / 2,
            margin: const EdgeInsets.all(1),
            padding: const EdgeInsets.all(0),
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: null,
              child: Align(
                alignment: Alignment.center,
                child: Container(
                  width:
                      screenWidth(context) *
                      0.725 *
                      0.5, // 注意：原代码外层是 /2，内层是 *0.725，这里为了适配比例做了调整
                  height: screenWidth(context) * 0.725 * 0.5,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: DecorationImage(
                      // 这里使用了随机生成的图片路径
                      image: AssetImage(_randomImagePath),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: Center(
                    child: CustomPaint(
                      painter: CircleBorderWithGlow(
                        color: Colors.amber[100]!,
                        strokeWidth: 2,
                        glowRadius: 5, // 光晕半径
                      ),
                      child: Container(),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            "暂无内容，快来发布第一篇吧！",
            style: TextStyle(
              color: Colors.grey,
              fontSize: 14,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class CircleBorderWithGlow extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double glowRadius;

  CircleBorderWithGlow({
    required this.color,
    required this.strokeWidth,
    required this.glowRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2 - glowRadius;

    final glowPaint = Paint()
      ..color = color.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth + glowRadius * 2
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, glowRadius);

    canvas.drawCircle(center, radius + glowRadius, glowPaint);

    final borderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}
