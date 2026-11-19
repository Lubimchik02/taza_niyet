import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n_x.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_card.dart';
import 'auth_widgets.dart';

/// «Не могу войти»: запасной email, СМС, резервный код, поддержка.
/// Сервер на этапе 12 ограничит попытки и уведомит владельца аккаунта о восстановлении.
class RecoveryScreen extends StatelessWidget {
  const RecoveryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    Widget option(IconData icon, String title, String? sub, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(bottom: Space.x3),
          child: AppCard(
            onTap: onTap,
            child: Row(children: [
              Icon(icon, color: c.primaryStrong),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: context.text.titleMedium),
                  if (sub != null) Text(sub, style: context.text.bodyMedium?.copyWith(color: c.text2)),
                ]),
              ),
              Icon(Icons.chevron_right_rounded, color: c.text2),
            ]),
          ),
        );

    return AuthScaffold(
      title: l.recoveryTitle,
      body: l.recoveryBody,
      children: [
        option(Icons.alternate_email_rounded, l.recEmail, null, () => context.push(Routes.authIdentifier)),
        option(Icons.sms_outlined, l.recPhone, null, () => context.push(Routes.authIdentifier)),
        option(Icons.password_rounded, l.backupCode, null, () => context.push(Routes.authIdentifier)),
        option(Icons.support_agent_rounded, l.recSupport, l.recSupportBody, () {
          // Чат поддержки — этап 10 (Настройки → Помощь).
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.stageSoon(10))));
        }),
      ],
    );
  }
}
