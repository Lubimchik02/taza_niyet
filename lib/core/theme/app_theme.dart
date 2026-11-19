import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'tokens.dart';

/// Типографика: Manrope. Размеры в pt, масштабируются системным размером шрифта.
TextTheme _textTheme(Color ink) {
  TextStyle s(double size, double line, FontWeight w) => TextStyle(
        fontFamily: 'Manrope',
        fontSize: size,
        height: line / size,
        fontWeight: w,
        color: ink,
        letterSpacing: size >= 26 ? -0.4 : 0,
      );
  return TextTheme(
    displaySmall: s(32, 40, FontWeight.w800), // display
    headlineMedium: s(26, 32, FontWeight.w700), // title-1
    titleLarge: s(20, 26, FontWeight.w700), // title-2
    titleMedium: s(17, 22, FontWeight.w700), // headline
    bodyLarge: s(15, 22, FontWeight.w500), // body
    bodyMedium: s(14, 20, FontWeight.w500), // callout
    labelLarge: s(13, 16, FontWeight.w700), // label
    labelSmall: s(12, 16, FontWeight.w600), // caption
  );
}

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.light ? AppColors.light : AppColors.dark;
  final text = _textTheme(c.text);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.primary,
    onPrimary: c.onPrimary,
    secondary: c.primaryStrong,
    onSecondary: brightness == Brightness.light ? Colors.white : c.onPrimary,
    error: c.danger,
    onError: c.onDanger,
    surface: c.surface,
    onSurface: c.text,
    surfaceContainerHighest: c.surface2,
    outline: c.outline,
    outlineVariant: c.outline,
  );

  OutlineInputBorder border(Color color, [double width = 0]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.sm),
        borderSide: width == 0 ? BorderSide.none : BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.bg,
    fontFamily: 'Manrope',
    textTheme: text,
    extensions: [c],
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: c.bg,
      foregroundColor: c.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      indicatorColor: c.lime,
      height: 68,
      labelTextStyle: WidgetStatePropertyAll(text.labelSmall),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.text : c.text2),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface2,
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: 14),
      hintStyle: text.bodyLarge?.copyWith(color: c.text2),
      labelStyle: text.bodyMedium?.copyWith(color: c.text2),
      border: border(c.outline),
      enabledBorder: border(c.outline),
      disabledBorder: border(c.outline),
      focusedBorder: border(c.primaryStrong, 2),
      errorBorder: border(c.danger, 1.5),
      focusedErrorBorder: border(c.danger, 2),
      errorStyle: text.labelSmall?.copyWith(color: c.danger),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface2,
      selectedColor: c.primary,
      labelStyle: text.labelLarge,
      secondaryLabelStyle: text.labelLarge?.copyWith(color: c.onPrimary),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x2),
      checkmarkColor: c.onPrimary,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.text,
      contentTextStyle: text.bodyMedium?.copyWith(color: c.bg),
      shape: const StadiumBorder(),
    ),
    dividerTheme: DividerThemeData(color: c.outline, space: 1, thickness: 1),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
  );
}

/// Короткий доступ к токенам: `context.colors`, `context.text`.
extension ThemeX on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
  TextTheme get text => Theme.of(this).textTheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}
