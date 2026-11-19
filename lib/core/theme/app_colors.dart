import 'package:flutter/material.dart';

/// Цветовые токены Taza Niyet для светлой и тёмной темы.
/// Контрасты текстовых пар ≥ 4.5:1 (посчитаны по WCAG).
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.outline,
    required this.text,
    required this.text2,
    required this.primary,
    required this.onPrimary,
    required this.primaryStrong,
    required this.lime,
    required this.tzFg,
    required this.tzBg,
    required this.danger,
    required this.onDanger,
    required this.warning,
    required this.soil,
    required this.soilDark,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color outline;
  final Color text;
  final Color text2;
  final Color primary;
  final Color onPrimary;
  final Color primaryStrong;
  final Color lime;
  final Color tzFg;
  final Color tzBg;
  final Color danger;
  final Color onDanger;
  final Color warning;
  final Color soil;
  final Color soilDark;

  static const light = AppColors(
    bg: Color(0xFFF4F7EC),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEEF3E3),
    outline: Color(0xFFE2E9D5),
    text: Color(0xFF1D2A10),
    text2: Color(0xFF5E6E4C),
    primary: Color(0xFF8CC914),
    onPrimary: Color(0xFF1F3300),
    primaryStrong: Color(0xFF3D6B00),
    lime: Color(0xFFDDFF99),
    tzFg: Color(0xFF3D6B00),
    tzBg: Color(0xFFDDFF99),
    danger: Color(0xFFB3261E),
    onDanger: Color(0xFFFFFFFF),
    warning: Color(0xFF8A5A00),
    soil: Color(0xFF8E5A2B),
    soilDark: Color(0xFF6E4321),
  );

  static const dark = AppColors(
    bg: Color(0xFF10160B),
    surface: Color(0xFF182112),
    surface2: Color(0xFF222D1A),
    outline: Color(0xFF2E3A24),
    text: Color(0xFFE8F0DC),
    text2: Color(0xFFA3B293),
    primary: Color(0xFFA6E22E),
    onPrimary: Color(0xFF1A2B00),
    primaryStrong: Color(0xFFA6E22E),
    lime: Color(0xFF34461C),
    tzFg: Color(0xFFA6E22E),
    tzBg: Color(0xFF34461C),
    danger: Color(0xFFFF8A80),
    onDanger: Color(0xFF3B0A06),
    warning: Color(0xFFFFC266),
    soil: Color(0xFFA8703C),
    soilDark: Color(0xFF7E5128),
  );

  @override
  AppColors copyWith({
    Color? bg,
    Color? surface,
    Color? surface2,
    Color? outline,
    Color? text,
    Color? text2,
    Color? primary,
    Color? onPrimary,
    Color? primaryStrong,
    Color? lime,
    Color? tzFg,
    Color? tzBg,
    Color? danger,
    Color? onDanger,
    Color? warning,
    Color? soil,
    Color? soilDark,
  }) =>
      AppColors(
        bg: bg ?? this.bg,
        surface: surface ?? this.surface,
        surface2: surface2 ?? this.surface2,
        outline: outline ?? this.outline,
        text: text ?? this.text,
        text2: text2 ?? this.text2,
        primary: primary ?? this.primary,
        onPrimary: onPrimary ?? this.onPrimary,
        primaryStrong: primaryStrong ?? this.primaryStrong,
        lime: lime ?? this.lime,
        tzFg: tzFg ?? this.tzFg,
        tzBg: tzBg ?? this.tzBg,
        danger: danger ?? this.danger,
        onDanger: onDanger ?? this.onDanger,
        warning: warning ?? this.warning,
        soil: soil ?? this.soil,
        soilDark: soilDark ?? this.soilDark,
      );

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      outline: l(outline, other.outline),
      text: l(text, other.text),
      text2: l(text2, other.text2),
      primary: l(primary, other.primary),
      onPrimary: l(onPrimary, other.onPrimary),
      primaryStrong: l(primaryStrong, other.primaryStrong),
      lime: l(lime, other.lime),
      tzFg: l(tzFg, other.tzFg),
      tzBg: l(tzBg, other.tzBg),
      danger: l(danger, other.danger),
      onDanger: l(onDanger, other.onDanger),
      warning: l(warning, other.warning),
      soil: l(soil, other.soil),
      soilDark: l(soilDark, other.soilDark),
    );
  }
}
