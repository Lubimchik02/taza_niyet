import 'profile_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n_x.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../auth/auth_controller.dart';
import '../shift/shift_controller.dart';
import '../shift/widgets/hours_format.dart';
import 'data/portfolio.dart';
import 'widgets/profile_widgets.dart';

/// Портфолио: только подтверждённые координатором часы + QR для проверки.
/// По ссылке открывается публичная страница проверки (веб, этап 12) — без телефона и почты.
class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final c = context.colors;
    final user = ref.watch(sessionProvider);
    final credits = ref.watch(creditsProvider);
    final totals = ref.watch(totalsProvider);
    final code = ref.watch(portfolioCodeProvider).valueOrNull ?? '…';
    final link = portfolioLink(code);

    return Scaffold(
      appBar: AppBar(title: Text(l.portfolioTitle)),
      body: ListView(padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.x8), children: [
        Text(user?.name ?? '', style: context.text.headlineSmall),
        const SizedBox(height: Space.x3),
        StatsRow(hours: totals.hours, tz: totals.tz, shifts: credits.where((x) => x.kind == CreditKind.shift).length),
        const SizedBox(height: Space.x4),
        AppCard(
          child: Column(children: [
            Semantics(
              label: l.verifyTitle,
              image: true,
              child: Container(
                padding: const EdgeInsets.all(Space.x3),
                // QR всегда на белом — так его читает любая камера, и в тёмной теме тоже.
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(Radii.sm)),
                child: QrImageView(data: link, size: 180, padding: EdgeInsets.zero, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF1D2A10)), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF1D2A10))),
              ),
            ),
            const SizedBox(height: Space.x3),
            Text(l.verifyTitle, style: context.text.titleMedium),
            const SizedBox(height: Space.x1),
            Text(l.verifyBody(code), textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(color: c.text2)),
            const SizedBox(height: Space.x2),
            InkWell(
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: link));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.copied)));
              },
              child: Text(link, style: context.text.labelLarge?.copyWith(color: c.primaryStrong)),
            ),
            const SizedBox(height: Space.x3),
            AppButton(
              label: l.shareLink,
              icon: Icons.ios_share_rounded,
              onPressed: () => Share.share(l.portfolioShareText(formatHours(context, totals.hours), totals.tz, link)),
            ),
          ]),
        ),
        const SizedBox(height: Space.x6),
        Semantics(header: true, child: Text(l.historyTitle, style: context.text.titleLarge)),
        const SizedBox(height: Space.x2),
        if (credits.isEmpty)
          Text(l.noHistoryB, style: context.text.bodyMedium?.copyWith(color: c.text2))
        else
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
            child: Column(children: [
              for (final cr in credits) ...[
                CreditTile(credit: cr),
                if (cr.kind == CreditKind.shift && cr.orgName.isNotEmpty)
                  Align(alignment: Alignment.centerLeft, child: Padding(
                    padding: const EdgeInsets.only(left: 36, bottom: Space.x1),
                    child: Text(l.issuedBy(cr.orgName), style: context.text.labelSmall?.copyWith(color: c.primaryStrong)),
                  )),
              ],
            ]),
          ),
      ]),
    );
  }
}
