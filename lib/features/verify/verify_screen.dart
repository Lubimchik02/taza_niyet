import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_x.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/state_views.dart';
import '../profile/profile_controller.dart';
import '../shift/widgets/hours_format.dart';

/// Ссылка tazaniyet.kz/v/<номер>, открытая в приложении. Без приложения откроется
/// публичная веб-страница с тем же содержимым (этап 12). Демо знает только свой номер.
class VerifyScreen extends ConsumerWidget {
  const VerifyScreen({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final c = context.colors;
    final now = DateTime.now();
    final date = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final res = ref.watch(verifyProvider(code));
    return Scaffold(
      appBar: AppBar(title: Text(l.verifyPageT)),
      body: res.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => ErrorState(title: l.errorNetworkTitle, body: l.errorNetworkBody, retryLabel: l.retry, onRetry: () => ref.invalidate(verifyProvider(code))),
        data: (r) => ListView(padding: const EdgeInsets.all(Space.screen), children: [
          Container(
            padding: const EdgeInsets.all(Space.x5),
            decoration: BoxDecoration(color: r != null ? c.lime : c.surface2, borderRadius: BorderRadius.circular(Radii.md)),
            child: Column(children: [
              Icon(r != null ? Icons.verified_rounded : Icons.gpp_bad_outlined, size: 56, color: r != null ? c.primaryStrong : c.danger),
              const SizedBox(height: Space.x3),
              Semantics(liveRegion: true, child: Text(r != null ? l.verifyValid : l.verifyInvalid, style: context.text.titleLarge, textAlign: TextAlign.center)),
              const SizedBox(height: Space.x1),
              Text(code.toUpperCase(), style: context.text.labelLarge?.copyWith(color: c.text2)),
              if (r != null) ...[
                const SizedBox(height: Space.x4),
                Text(r.name, style: context.text.headlineSmall),
                Text('${formatHours(context, r.hours)} · ${r.tz} Tz · ${l.profileShifts}: ${r.shifts}', style: context.text.titleMedium?.copyWith(color: c.primaryStrong)),
                const SizedBox(height: Space.x2),
                Text(l.verifyChecked(date), style: context.text.bodySmall?.copyWith(color: c.text2)),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
