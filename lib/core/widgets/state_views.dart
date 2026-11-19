import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'app_button.dart';
import 'sprout.dart';

/// Пустой экран: росток, заголовок, одна строка пояснения, одно действие.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, required this.body, this.actionLabel, this.onAction});

  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => _Frame(
        art: const SproutIllustration(size: 140),
        title: title,
        body: body,
        action: actionLabel == null
            ? null
            : AppButton(label: actionLabel!, onPressed: onAction, expand: false),
      );
}

/// Экран ошибки: причина простыми словами и «Повторить».
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.title, required this.body, required this.retryLabel, required this.onRetry});

  final String title;
  final String body;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _Frame(
        art: Icon(Icons.cloud_off_rounded, size: 72, color: context.colors.text2),
        title: title,
        body: body,
        action: AppButton(
          label: retryLabel,
          onPressed: onRetry,
          kind: AppButtonKind.secondary,
          icon: Icons.refresh_rounded,
          expand: false,
        ),
      );
}

class _Frame extends StatelessWidget {
  const _Frame({required this.art, required this.title, required this.body, this.action});

  final Widget art;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(Space.x8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ExcludeSemantics(child: art),
            const SizedBox(height: Space.x5),
            Text(title, textAlign: TextAlign.center, style: context.text.titleLarge),
            const SizedBox(height: Space.x2),
            Text(body, textAlign: TextAlign.center, style: context.text.bodyLarge?.copyWith(color: context.colors.text2)),
            if (action != null) ...[const SizedBox(height: Space.x6), action!],
          ]),
        ),
      );
}

/// Плашка «нет сети» поверх экрана.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
        color: c.text,
        child: Row(children: [
          Icon(Icons.wifi_off_rounded, size: 18, color: c.bg),
          const SizedBox(width: Space.x2),
          Expanded(child: Text(message, style: context.text.bodyMedium?.copyWith(color: c.bg))),
        ]),
      ),
    );
  }
}
