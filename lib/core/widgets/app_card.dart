import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Карточка: surface, радиус md, тень e1 в светлой теме (в тёмной — без тени).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(Space.x4)});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final radius = BorderRadius.circular(Radii.md);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: radius,
        boxShadow: context.isDark ? null : Shadows.e1,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Плашка баллов Tz. Смысл передаётся текстом, не только цветом.
class TzBadge extends StatelessWidget {
  const TzBadge({super.key, required this.amount, this.semanticsLabel});

  final int amount;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sign = amount > 0 ? '+' : '';
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x1 + 2),
        decoration: BoxDecoration(color: c.tzBg, borderRadius: BorderRadius.circular(Radii.pill)),
        child: Text('$sign$amount Tz', style: context.text.labelLarge?.copyWith(color: c.tzFg)),
      ),
    );
  }
}
