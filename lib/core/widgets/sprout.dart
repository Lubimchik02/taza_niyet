import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Росток в земле — фирменная иллюстрация пустых экранов (как на заставке).
class SproutIllustration extends StatelessWidget {
  const SproutIllustration({super.key, this.size = 140});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      width: size,
      height: size * 0.6,
      child: CustomPaint(painter: _SproutPainter(leaf: c.primary, stem: c.primaryStrong, soil: c.soil, soilDark: c.soilDark)),
    );
  }
}

class _SproutPainter extends CustomPainter {
  _SproutPainter({required this.leaf, required this.stem, required this.soil, required this.soilDark});

  final Color leaf;
  final Color stem;
  final Color soil;
  final Color soilDark;

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем в системе координат 300×180 и масштабируем.
    canvas.scale(size.width / 300, size.height / 180);
    final soilBody = Path()
      ..moveTo(62, 134)
      ..quadraticBezierTo(62, 120, 150, 118)
      ..quadraticBezierTo(238, 120, 238, 134)
      ..lineTo(238, 146)
      ..quadraticBezierTo(238, 166, 214, 166)
      ..lineTo(86, 166)
      ..quadraticBezierTo(62, 166, 62, 146)
      ..close();
    canvas.drawPath(soilBody, Paint()..color = soilDark);
    canvas.drawOval(Rect.fromCenter(center: const Offset(150, 128), width: 176, height: 24), Paint()..color = soil);

    final stemPaint = Paint()
      ..color = stem
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(Path()..moveTo(150, 128)..cubicTo(150, 108, 148, 92, 151, 76), stemPaint);

    final left = Path()
      ..moveTo(151, 80)
      ..cubicTo(143, 56, 113, 42, 81, 48)
      ..cubicTo(89, 74, 121, 86, 151, 80)
      ..close();
    final right = Path()
      ..moveTo(151, 88)
      ..cubicTo(159, 68, 183, 58, 209, 62)
      ..cubicTo(201, 83, 175, 93, 151, 88)
      ..close();
    canvas.drawPath(left, Paint()..color = leaf);
    canvas.drawPath(right, Paint()..color = Color.lerp(leaf, Colors.white, 0.15)!);
  }

  @override
  bool shouldRepaint(_SproutPainter old) => old.leaf != leaf || old.soil != soil;
}
