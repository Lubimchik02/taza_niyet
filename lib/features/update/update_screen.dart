import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/l10n_x.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/sprout.dart';

/// Принудительное обновление: версия ниже минимальной. Экран нельзя закрыть «Назад».
class UpdateScreen extends ConsumerWidget {
  const UpdateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final url = ref.watch(appConfigProvider).storeUrl;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Space.x6),
            child: Column(children: [
              const Spacer(),
              const SproutIllustration(size: 140),
              const SizedBox(height: Space.x6),
              Text(l.updateRequiredT, style: context.text.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: Space.x3),
              Text(l.updateRequiredB, style: context.text.bodyLarge?.copyWith(color: context.colors.text2), textAlign: TextAlign.center),
              const Spacer(flex: 2),
              AppButton(label: l.updateAction, icon: Icons.system_update_rounded, onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
            ]),
          ),
        ),
      ),
    );
  }
}
