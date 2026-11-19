import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n_x.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/sprout.dart';
import '../data/org_repository.dart';
import '../org_controller.dart';

/// Заявка отправлена / одобрена / отклонена.
class OrgPendingScreen extends ConsumerWidget {
  const OrgPendingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final c = context.colors;
    final m = ref.watch(membershipProvider);

    if (m == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go(Routes.home));
      return const SizedBox.shrink();
    }
    if (m.status == MembershipStatus.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go(Routes.home));
      return const SizedBox.shrink();
    }
    final rejected = m.status == MembershipStatus.rejected;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(Space.x6),
          child: Column(children: [
            const Spacer(),
            ExcludeSemantics(
              child: rejected
                  ? Icon(Icons.do_not_disturb_on_outlined, size: 72, color: c.text2)
                  : const SproutIllustration(size: 160),
            ),
            const SizedBox(height: Space.x6),
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(rejected ? l.rejectedTitle : l.pendingTitle, textAlign: TextAlign.center, style: context.text.headlineMedium),
            ),
            const SizedBox(height: Space.x2),
            Text(
              rejected ? l.rejectedBody(m.orgName) : l.pendingBody(m.orgName),
              textAlign: TextAlign.center,
              style: context.text.bodyLarge?.copyWith(color: c.text2),
            ),
            if (!rejected) ...[
              const SizedBox(height: Space.x4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.primaryStrong)),
                const SizedBox(width: Space.x2),
                Text(l.orgPendingBanner(m.orgName), style: context.text.labelSmall?.copyWith(color: c.text2)),
              ]),
            ],
            const Spacer(),
            if (rejected)
              AppButton(
                label: l.chooseAnother,
                onPressed: () async {
                  await ref.read(membershipProvider.notifier).cancel();
                  if (context.mounted) context.pushReplacement(Routes.org);
                },
              )
            else ...[
              AppButton(label: l.browseMeanwhile, onPressed: () => context.go(Routes.home)),
              const SizedBox(height: Space.x3),
              AppButton(
                label: l.cancelRequest,
                kind: AppButtonKind.ghost,
                onPressed: () async {
                  await ref.read(membershipProvider.notifier).cancel();
                  if (context.mounted) context.pushReplacement(Routes.org);
                },
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
