import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/settings/settings_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../auth_controller.dart';
import '../data/auth_repository.dart';

/// Общий каркас экранов входа: «Назад», заголовок, пояснение, содержимое, кнопка внизу.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, this.body, required this.children, this.bottom, this.showBack = true});

  final String title;
  final String? body;
  final List<Widget> children;
  final Widget? bottom;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(automaticallyImplyLeading: showBack),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x6), children: [
                Semantics(header: true, child: Text(title, style: context.text.headlineMedium)),
                if (body != null) ...[
                  const SizedBox(height: Space.x2),
                  Text(body!, style: context.text.bodyLarge?.copyWith(color: context.colors.text2)),
                ],
                const SizedBox(height: Space.x6),
                ...children,
              ]),
            ),
            if (bottom != null) Padding(padding: const EdgeInsets.all(Space.x4), child: bottom),
          ]),
        ),
      );
}

/// Ошибка под полем или над кнопкой: значок + текст (смысл не только цветом), объявляется VoiceOver.
class InlineError extends StatelessWidget {
  const InlineError(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedSize(
      duration: Motion.of(context, Motion.base),
      child: message == null
          ? const SizedBox(width: double.infinity)
          : Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.only(top: Space.x3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.error_outline_rounded, size: 20, color: c.danger),
                  const SizedBox(width: Space.x2),
                  Expanded(child: Text(message!, style: context.text.bodyMedium?.copyWith(color: c.danger))),
                ]),
              ),
            ),
    );
  }
}

/// Поле для 6-значного кода: автоподстановка из СМС/почты, цифровая клавиатура, автоотправка.
class CodeField extends StatelessWidget {
  const CodeField({super.key, required this.controller, required this.onCompleted, this.hasError = false, this.enabled = true, this.autofocus = true});

  final TextEditingController controller;
  final ValueChanged<String> onCompleted;
  final bool hasError;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      autofillHints: const [AutofillHints.oneTimeCode],
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
      style: context.text.displaySmall?.copyWith(letterSpacing: 14, fontFeatures: const [FontFeature.tabularFigures()]),
      decoration: InputDecoration(
        hintText: '••••••',
        hintStyle: context.text.displaySmall?.copyWith(letterSpacing: 14, color: c.outline),
        enabledBorder: hasError
            ? OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.sm), borderSide: BorderSide(color: c.danger, width: 1.5))
            : null,
      ),
      onChanged: (v) {
        if (v.length == 6) onCompleted(v);
      },
    );
  }
}

/// После успешного входа: сохранить сессию и перейти дальше.
void goAfterSignIn(BuildContext context, WidgetRef ref, AuthUser user) {
  ref.read(sessionProvider.notifier).set(user);
  ref.read(authFlowProvider.notifier).reset();
  context.go(nextAfterAuth(ref, user));
}

/// Порядок входа: регистрация/вход → профиль → один раз вопрос о местоположении → главная.
/// Организацию не требуем: её мягко предлагает главная после инструкции.
String nextAfterAuth(WidgetRef ref, AuthUser user) {
  if (user.needsProfile) return Routes.authProfile;
  if (!ref.read(settingsProvider).locationAsked) return Routes.locationSetup;
  return Routes.home;
}
