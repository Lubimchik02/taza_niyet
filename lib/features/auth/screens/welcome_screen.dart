import '../../../core/backend/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n_x.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/leaf.dart';
import '../auth_controller.dart';
import '../data/auth_repository.dart';
import 'auth_widgets.dart';

/// Приветствие: Apple, Google, ключ доступа (passkey), email или телефон.
/// Бесплатные способы — первыми: СМС-коды платные.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

enum _Busy { none, apple, google, passkey }

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  _Busy _busy = _Busy.none;
  String? _error;

  Future<void> _run(_Busy which, Future<SignInResult> Function() action) async {
    setState(() {
      _busy = which;
      _error = null;
    });
    try {
      final r = await action();
      if (!mounted) return;
      if (r is SignedIn) {
        goAfterSignIn(context, ref, r.user);
      } else if (r is NeedsSecondFactor) {
        ref.read(authFlowProvider.notifier).setPending(r.pendingUser);
        context.push(Routes.auth2fa);
      }
    } catch (e) {
      if (mounted) setState(() => _error = authErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final repo = ref.read(authRepositoryProvider);
    final busy = _busy != _Busy.none;

    return AuthScaffold(
      showBack: false,
      title: l.authWelcomeTitle,
      body: l.authWelcomeBody,
      children: [
        Center(child: LeafMark(size: 72, color: c.primary)),
        const SizedBox(height: Space.x8),
        // По правилам App Store: раз есть вход через Google, вход через Apple обязателен.
        ...[
          AppButton(
            label: l.withApple,
            icon: Icons.apple,
            kind: AppButtonKind.secondary,
            loading: _busy == _Busy.apple,
            onPressed: busy ? null : () => _run(_Busy.apple, repo.signInWithApple),
          ),
          const SizedBox(height: Space.x3),
        ],
        AppButton(
          label: l.withGoogle,
          icon: Icons.account_circle_outlined, // официальная кнопка Google — на этапе 12
          kind: AppButtonKind.secondary,
          loading: _busy == _Busy.google,
          onPressed: busy ? null : () => _run(_Busy.google, repo.signInWithGoogle),
        ),
        // Ключи доступа: в Supabase Auth пока нет — на сервере кнопку не показываем.
        if (!Backend.enabled) ...[
          const SizedBox(height: Space.x3),
          AppButton(
            label: l.withPasskey,
            icon: Icons.key_rounded,
            kind: AppButtonKind.secondary,
            loading: _busy == _Busy.passkey,
            onPressed: busy ? null : () => _run(_Busy.passkey, repo.signInWithPasskey),
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x4),
          child: Row(children: [
            const Expanded(child: Divider()),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.x3),
              child: Text(l.orWord, style: context.text.bodyMedium?.copyWith(color: c.text2)),
            ),
            const Expanded(child: Divider()),
          ]),
        ),
        AppButton(
          label: l.withEmailPhone,
          icon: Icons.mail_outline_rounded,
          onPressed: busy ? null : () => context.push(Routes.authIdentifier),
        ),
        InlineError(_error),
        const SizedBox(height: Space.x4),
        Center(
          child: TextButton(
            onPressed: () => context.push(Routes.authRecovery),
            style: TextButton.styleFrom(minimumSize: const Size(Hit.min, Hit.min)),
            child: Text(l.cantSignIn),
          ),
        ),
        const SizedBox(height: Space.x2),
        // Ссылки на условия и политику — этап 13 (тексты документов).
        Text(l.legal, textAlign: TextAlign.center, style: context.text.labelSmall?.copyWith(color: c.text2)),
      ],
    );
  }
}
