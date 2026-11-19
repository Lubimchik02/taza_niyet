import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/leaf.dart';
import 'leaf_fall.dart';

/// Заставка: лист падает, ложится на землю, вырастает росток, появляется «Taza Niyet».
/// [full] = первый запуск (≈4,4 с). Потом — короткая версия (≈0,8 с), чтобы не задерживать.
/// При «Уменьшении движения» — сразу готовая картинка.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.full, required this.onDone, required this.skipLabel});

  final bool full;
  final VoidCallback onDone;
  final String skipLabel;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

/// Отрезки шкалы времени (секунды) для полной версии.
abstract final class _T {
  static const total = 4.4;
  static const fall = (0.08, 2.18);
  static const sink = (2.18, 2.53);
  static const soil = (0.1, 0.5);
  static const stem = (2.3, 2.9);
  static const leftLeaf = (2.7, 3.2);
  static const rightLeaf = (2.9, 3.4);
  static const title = (3.2, 3.7);
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _done = false;
  late bool _animate;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.isAnimating || _c.value > 0) return;
    _animate = widget.full && !Motion.reduced(context);
    if (_animate) {
      _c.duration = const Duration(milliseconds: 4400);
      _c.forward().whenComplete(_finish);
    } else {
      _c.value = 1; // готовая картинка
      Future<void>.delayed(Duration(milliseconds: widget.full ? 1200 : 800), _finish);
    }
  }

  void _finish() {
    if (_done || !mounted) return;
    _done = true;
    widget.onDone();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _seg(double t, (double, double) s) => ((t - s.$1) / (s.$2 - s.$1)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: Stack(children: [
          LayoutBuilder(builder: (context, box) {
            // Сцена 300×470, увеличенная до ×1,18, но не больше экрана.
            final k = math.min(1.18, math.min(box.maxWidth / 300, (box.maxHeight - 80) / 470));
            return Center(
              child: Semantics(
                label: 'Taza Niyet',
                excludeSemantics: true,
                child: SizedBox(
                  width: 300 * k,
                  height: 470 * k,
                  child: FittedBox(
                    child: SizedBox(
                      width: 300,
                      height: 470,
                      child: AnimatedBuilder(
                        animation: _c,
                        builder: (context, _) => _scene(context, _c.value * _T.total),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
          if (_animate)
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.all(Space.x3),
                  child: TextButton(
                    onPressed: _finish,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(Hit.min, Hit.min),
                      backgroundColor: c.surface2,
                      foregroundColor: c.text2,
                      shape: const StadiumBorder(),
                    ),
                    child: Text(widget.skipLabel),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _scene(BuildContext context, double t) {
    final c = context.colors;
    final fallP = _seg(t, _T.fall);
    final sinkP = _seg(t, _T.sink);
    final pose = leafFallPose(fallP);
    final leafVisible = _animate && t < _T.sink.$2;
    final ease = Curves.easeOutBack;
    return Stack(clipBehavior: Clip.none, children: [
      // Росток и земля
      Positioned.fill(
        child: CustomPaint(
          painter: _PlantPainter(
            soil: Curves.easeOut.transform(_seg(t, _T.soil)),
            stem: Curves.easeOut.transform(_seg(t, _T.stem)),
            left: ease.transform(_seg(t, _T.leftLeaf)),
            right: ease.transform(_seg(t, _T.rightLeaf)),
            leafColor: c.primary,
            leafColor2: Color.lerp(c.primary, Colors.white, 0.15)!,
            vein: c.primaryStrong,
            stemColor: Color.lerp(c.primary, c.primaryStrong, 0.3)!,
            soilTop: c.soil,
            soilBody: c.soilDark,
          ),
        ),
      ),
      // Падающий лист — плоский, лежит горизонтально, качается
      if (leafVisible)
        Positioned(
          left: 170 + pose.dx,
          top: -32 + pose.dy,
          child: Opacity(
            opacity: (1 - sinkP) * (fallP / 0.05).clamp(0.0, 1.0),
            child: Transform.rotate(
              angle: pose.rot * math.pi / 180,
              child: Transform.scale(
                scale: 1 - 0.3 * sinkP,
                child: LeafMark(size: 48, color: c.primary),
              ),
            ),
          ),
        ),
      // Название (не переводится)
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Opacity(
          opacity: _seg(t, _T.title),
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - _seg(t, _T.title))),
            child: Text(
              'Taza Niyet',
              textAlign: TextAlign.center,
              style: context.text.displaySmall?.copyWith(color: c.text, letterSpacing: -1),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Земля, стебель и два листика ростка. Координаты — сцена 300×470.
class _PlantPainter extends CustomPainter {
  _PlantPainter({
    required this.soil,
    required this.stem,
    required this.left,
    required this.right,
    required this.leafColor,
    required this.leafColor2,
    required this.vein,
    required this.stemColor,
    required this.soilTop,
    required this.soilBody,
  });

  final double soil, stem, left, right;
  final Color leafColor, leafColor2, vein, stemColor, soilTop, soilBody;

  static const double _oy = 252; // верх области ростка на сцене

  @override
  void paint(Canvas canvas, Size size) {
    canvas.translate(0, _oy);
    // Земля
    if (soil > 0) {
      canvas.save();
      canvas.translate(0, 10 * (1 - soil));
      final a = (soil * 255).round();
      final body = Path()
        ..moveTo(62, 134)
        ..quadraticBezierTo(62, 120, 150, 118)
        ..quadraticBezierTo(238, 120, 238, 134)
        ..lineTo(238, 146)
        ..quadraticBezierTo(238, 166, 214, 166)
        ..lineTo(86, 166)
        ..quadraticBezierTo(62, 166, 62, 146)
        ..close();
      canvas.drawPath(body, Paint()..color = soilBody.withAlpha(a));
      canvas.drawOval(Rect.fromCenter(center: const Offset(150, 128), width: 176, height: 24), Paint()..color = soilTop.withAlpha(a));
      canvas.restore();
    }
    // Стебель — «прорисовывается» снизу вверх
    if (stem > 0) {
      final p = Path()..moveTo(150, 128)..cubicTo(150, 108, 148, 92, 151, 76);
      final m = p.computeMetrics().first;
      canvas.drawPath(
        m.extractPath(0, m.length * stem),
        Paint()
          ..color = stemColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..strokeCap = StrokeCap.round,
      );
    }
    _leaf(canvas, const Offset(151, 80), left, false);
    _leaf(canvas, const Offset(151, 88), right, true);
  }

  void _leaf(Canvas canvas, Offset at, double k, bool mirror) {
    if (k <= 0) return;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.scale(k * (mirror ? -0.83 : 1), k * (mirror ? 0.83 : 1));
    final shape = Path()
      ..moveTo(0, 0)
      ..cubicTo(-8, -24, -38, -38, -70, -32)
      ..cubicTo(-62, -6, -30, 6, 0, 0)
      ..close();
    canvas.drawPath(shape, Paint()..color = mirror ? leafColor2 : leafColor);
    canvas.drawPath(
      Path()..moveTo(-4, -3)..cubicTo(-22, -14, -42, -24, -62, -29),
      Paint()
        ..color = vein
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PlantPainter o) =>
      o.soil != soil || o.stem != stem || o.left != left || o.right != right || o.leafColor != leafColor;
}
