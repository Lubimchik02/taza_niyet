import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_x.dart';
import '../../core/router/app_router.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_button.dart';
import '../org/org_controller.dart';

/// Один раз после регистрации: объясняем, зачем местоположение, и только по кнопке
/// показываем системный запрос. «Не сейчас» не блокирует — город можно выбрать позже.
class LocationSetupScreen extends ConsumerStatefulWidget {
  const LocationSetupScreen({super.key});

  @override
  ConsumerState<LocationSetupScreen> createState() => _LocationSetupScreenState();
}

class _LocationSetupScreenState extends ConsumerState<LocationSetupScreen> {
  bool _busy = false;

  Future<void> _finish({required bool ask}) async {
    setState(() => _busy = true);
    if (ask) await ref.read(locationServiceProvider).request();
    await ref.read(settingsProvider.notifier).markLocationAsked();
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.x6),
          child: Column(children: [
            const Spacer(),
            ExcludeSemantics(
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(color: c.lime, shape: BoxShape.circle),
                child: Icon(Icons.near_me_rounded, size: 52, color: c.primaryStrong),
              ),
            ),
            const SizedBox(height: Space.x6),
            Semantics(header: true, child: Text(l.locSetupTitle, style: context.text.headlineMedium, textAlign: TextAlign.center)),
            const SizedBox(height: Space.x3),
            Text(l.locSetupBody, style: context.text.bodyLarge?.copyWith(color: c.text2), textAlign: TextAlign.center),
            const Spacer(flex: 2),
            AppButton(label: l.locAllow, loading: _busy, onPressed: _busy ? null : () => _finish(ask: true)),
            const SizedBox(height: Space.x2),
            AppButton(label: l.notNow, kind: AppButtonKind.ghost, onPressed: _busy ? null : () => _finish(ask: false)),
          ]),
        ),
      ),
    );
  }
}
