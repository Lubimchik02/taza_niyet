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

/// Инструкция «Как стать волонтёром»: 5 шагов простым языком + важные правила.
/// Открывается иконкой-решёткой в шапке главной. Для новичков и школьников —
/// короткие фразы, крупные номера шагов, без терминов.
class GuideScreen extends ConsumerStatefulWidget {
  const GuideScreen({super.key});

  @override
  ConsumerState<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends ConsumerState<GuideScreen> {
  @override
  void initState() {
    super.initState();
    // Открыл — значит ознакомился: на главной вместо инструкции появится предложение организации.
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(settingsProvider.notifier).markGuideSeen());
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final hasOrg = ref.watch(membershipProvider) != null;
    final steps = [
      (Icons.groups_2_rounded, l.g1T, l.g1B),
      (Icons.map_rounded, l.g2T, l.g2B),
      (Icons.group_add_rounded, l.g3T, l.g3B),
      (Icons.where_to_vote_rounded, l.g4T, l.g4B),
      (Icons.workspace_premium_rounded, l.g5T, l.g5B),
    ];
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x6), children: [
              Semantics(header: true, child: Text(l.guideTitle, style: context.text.headlineMedium)),
              const SizedBox(height: Space.x2),
              Text(l.guideLead, style: context.text.bodyLarge?.copyWith(color: c.text2)),
              const SizedBox(height: Space.x6),
              for (var i = 0; i < steps.length; i++)
                _Step(n: i + 1, icon: steps[i].$1, title: steps[i].$2, body: steps[i].$3, last: i == steps.length - 1),
              const SizedBox(height: Space.x4),
              Container(
                padding: const EdgeInsets.all(Space.x4),
                decoration: BoxDecoration(color: c.lime, borderRadius: BorderRadius.circular(Radii.md)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.info_outline_rounded, color: c.primaryStrong),
                    const SizedBox(width: Space.x2),
                    Semantics(header: true, child: Text(l.rulesTitle, style: context.text.titleMedium)),
                  ]),
                  const SizedBox(height: Space.x2),
                  for (final r in [l.rule1, l.rule2, l.rule3])
                    Padding(
                      padding: const EdgeInsets.only(top: Space.x2),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7, right: Space.x3),
                          child: Container(width: 6, height: 6, decoration: BoxDecoration(color: c.primaryStrong, shape: BoxShape.circle)),
                        ),
                        Expanded(child: Text(r, style: context.text.bodyMedium)),
                      ]),
                    ),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.x4),
            child: hasOrg
                ? AppButton(label: l.gotIt, onPressed: () => context.pop())
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    AppButton(label: l.guideDone, onPressed: () => context.pushReplacement(Routes.org)),
                    const SizedBox(height: Space.x2),
                    AppButton(label: l.later, kind: AppButtonKind.ghost, onPressed: () => context.pop()),
                  ]),
          ),
        ]),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.icon, required this.title, required this.body, required this.last});

  final int n;
  final IconData icon;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return MergeSemantics(
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Номер шага + линия к следующему — видно, что это последовательность.
          Column(children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
              child: Text('$n', style: context.text.titleMedium?.copyWith(color: c.onPrimary, fontWeight: FontWeight.w800)),
            ),
            if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: Space.x1), color: c.outline)),
          ]),
          const SizedBox(width: Space.x4),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : Space.x5, top: Space.x1),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(title, style: context.text.titleMedium)),
                  Icon(icon, size: 22, color: c.primaryStrong),
                ]),
                const SizedBox(height: Space.x1),
                Text(body, style: context.text.bodyMedium?.copyWith(color: c.text2)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}
