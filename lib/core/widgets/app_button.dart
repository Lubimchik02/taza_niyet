import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../ui/haptics.dart';

enum AppButtonKind { primary, secondary, ghost, danger }

/// Кнопка со всеми состояниями: обычное, нажатое (затемнение 8% + масштаб 0.98),
/// неактивное (38%), загрузка. Высота ≥ 48, работает с VoiceOver/TalkBack и клавиатурой.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = AppButtonKind.primary,
    this.loading = false,
    this.icon,
    this.expand = true,
    this.haptic = HapticKind.medium,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final bool loading;
  final IconData? icon;
  final bool expand;
  final HapticKind haptic;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = widget.onPressed != null && !widget.loading;
    final disabled = widget.onPressed == null && !widget.loading;

    final (Color bg, Color fg, Border? border) = switch (widget.kind) {
      AppButtonKind.primary => (c.primary, c.onPrimary, null),
      AppButtonKind.secondary => (c.surface2, c.text, null),
      AppButtonKind.ghost => (Colors.transparent, c.primaryStrong, null),
      AppButtonKind.danger => (Colors.transparent, c.danger, Border.all(color: c.danger, width: 1.5)),
    };
    final pressedBg = Color.alphaBlend(fg.withValues(alpha: 0.08), bg == Colors.transparent ? c.bg : bg);
    final fast = Motion.of(context, Motion.fast);

    final content = widget.loading
        ? SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: fg),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 20, color: fg),
                const SizedBox(width: Space.x2),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.labelLarge?.copyWith(color: fg, fontSize: 16),
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      value: widget.loading ? '…' : null,
      excludeSemantics: true,
      onTap: enabled ? _tap : null,
      child: AnimatedOpacity(
        opacity: disabled ? 0.38 : 1,
        duration: fast,
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1,
          duration: fast,
          curve: Motion.curve,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const StadiumBorder(),
              splashFactory: NoSplash.splashFactory,
              onTap: enabled ? _tap : null,
              onHighlightChanged: (v) => setState(() => _pressed = v),
              child: AnimatedContainer(
                duration: fast,
                constraints: const BoxConstraints(minHeight: 52, minWidth: Hit.min),
                padding: const EdgeInsets.symmetric(horizontal: Space.x6),
                decoration: ShapeDecoration(
                  color: _pressed ? pressedBg : bg,
                  shape: StadiumBorder(side: border?.top ?? BorderSide.none),
                ),
                child: Row(
                  mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [Flexible(child: content)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _tap() {
    Haptics.play(widget.haptic);
    widget.onPressed?.call();
  }
}
