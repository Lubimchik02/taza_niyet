import 'package:flutter/material.dart';

/// Отступы — сетка 4/8 pt.
abstract final class Space {
  static const double x1 = 4;
  static const double x2 = 8;
  static const double x3 = 12;
  static const double x4 = 16;
  static const double x5 = 20;
  static const double x6 = 24;
  static const double x8 = 32;
  static const double x10 = 40;
  static const double x12 = 48;

  /// Поля экрана слева и справа.
  static const double screen = 16;
}

/// Радиусы скругления.
abstract final class Radii {
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 18;
  static const double lg = 24;
  static const double pill = 999;
}

/// Минимальная зона нажатия: 44 pt (iOS) / 48 dp (Android) — берём большее.
abstract final class Hit {
  static const double min = 48;
}

/// Длительности и кривая анимаций (150–300 мс).
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration base = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 300);
  static const Curve curve = Cubic(0.2, 0, 0, 1);

  /// Учитывает системное «Уменьшение движения»: тогда анимаций нет.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

/// Тени. В тёмной теме вместо теней используем более светлый surface.
abstract final class Shadows {
  static const List<BoxShadow> e1 = [
    BoxShadow(color: Color(0x0F000000), offset: Offset(0, 1), blurRadius: 2),
  ];
  static const List<BoxShadow> e2 = [
    BoxShadow(color: Color(0x1A000000), offset: Offset(0, 4), blurRadius: 12),
  ];
  static const List<BoxShadow> e3 = [
    BoxShadow(color: Color(0x24000000), offset: Offset(0, 10), blurRadius: 34),
  ];
}
