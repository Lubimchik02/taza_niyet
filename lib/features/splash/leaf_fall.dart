import 'dart:math' as math;

/// Положение падающего листа в момент p ∈ [0, 1].
/// Лист качается как маятник (1,5 качания), лежит плашмя и мягко садится на землю.
/// dx, dy — смещение в точках сцены 300×470, rot — угол в градусах.
typedef LeafPose = ({double dx, double dy, double rot});

const double kFallDx = -44; // куда сместиться по горизонтали к концу
const double kFallDy = 362; // глубина падения до земли
const double kSwing = 90; // длина «маятника»
const double kSwingAngle = 0.85; // максимальный угол качания, рад

LeafPose leafFallPose(double p) {
  p = p.clamp(0.0, 1.0);
  final phi = kSwingAngle * math.sin(3 * math.pi * p) * (1 - 0.5 * p);
  final dx = kFallDx * p + kSwing * math.sin(phi);
  final dy = kFallDy * (0.12 * p * p + 0.88 * p) - kSwing * 0.8 * (1 - math.cos(phi));
  final rot = 45 + phi * 57.2958 * 0.55; // 45° — лист лежит горизонтально
  return (dx: dx, dy: dy, rot: rot);
}
