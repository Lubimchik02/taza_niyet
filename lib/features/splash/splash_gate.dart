import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_x.dart';
import '../../core/router/app_router.dart';
import '../../core/settings/settings_controller.dart';
import '../auth/auth_controller.dart';
import 'splash_screen.dart';

/// Решает, какую заставку показать и куда идти после неё.
/// Первый запуск: полная анимация → онбординг. Дальше: короткая → главная
/// или экран входа, если сессии нет.
class SplashGate extends ConsumerWidget {
  const SplashGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seen = ref.read(settingsProvider).onboardingSeen;
    final signedIn = ref.read(sessionProvider) != null;
    return SplashScreen(
      full: !seen,
      skipLabel: context.l.skip,
      onDone: () => context.go(!seen ? Routes.onboarding : (signedIn ? Routes.home : Routes.auth)),
    );
  }
}
