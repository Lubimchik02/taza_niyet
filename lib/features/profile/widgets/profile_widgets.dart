import 'package:flutter/material.dart';

import '../../../core/l10n_x.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../shift/shift_controller.dart';
import '../../shift/widgets/hours_format.dart';
import '../data/portfolio.dart';

/// Три числа в ряд: часы · Tz · смены.
class StatsRow extends StatelessWidget {
  const StatsRow({super.key, required this.hours, required this.tz, required this.shifts});
  final double hours;
  final int tz, shifts;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    Widget tile(String value, String label) => Expanded(
          child: MergeSemantics(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: Space.x3),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.md), border: Border.all(color: c.outline)),
              child: Column(children: [
                Text(value, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800, color: c.primaryStrong)),
                Text(label, style: context.text.labelMedium?.copyWith(color: c.text2)),
              ]),
            ),
          ),
        );
    return Row(children: [
      tile(formatHours(context, hours), l.profileHours),
      const SizedBox(width: Space.x2),
      tile('$tz', l.profileTz),
      const SizedBox(width: Space.x2),
      tile('$shifts', l.profileShifts),
    ]);
  }
}

String achievementTitle(BuildContext context, AchievementId id) {
  final l = context.l;
  return switch (id) {
    AchievementId.first => l.achFirst,
    AchievementId.shifts3 => l.achShifts3,
    AchievementId.shifts5 => l.achShifts5,
    AchievementId.h10 => l.achH10,
    AchievementId.h50 => l.achH50,
    AchievementId.senior => l.achSenior,
  };
}

IconData achievementIcon(AchievementId id) => switch (id) {
      AchievementId.first => Icons.eco_rounded,
      AchievementId.shifts3 => Icons.looks_3_rounded,
      AchievementId.shifts5 => Icons.groups_2_rounded,
      AchievementId.h10 => Icons.timer_rounded,
      AchievementId.h50 => Icons.workspace_premium_rounded,
      AchievementId.senior => Icons.shield_rounded,
    };

/// Значок достижения: получено — цветной, нет — серый с прогрессом.
class AchievementBadge extends StatelessWidget {
  const AchievementBadge({super.key, required this.a});
  final Achievement a;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    String n(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    final sub = a.earned ? l.achDone : l.achProgress(n(a.current), n(a.target));
    return Semantics(
      label: '${achievementTitle(context, a.id)}, $sub',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(Space.x3),
        decoration: BoxDecoration(color: a.earned ? c.lime : c.surface2, borderRadius: BorderRadius.circular(Radii.md)),
        child: Column(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(color: a.earned ? c.primary : c.outline, shape: BoxShape.circle),
            child: Icon(achievementIcon(a.id), color: a.earned ? c.onPrimary : c.text2),
          ),
          const SizedBox(height: Space.x2),
          Text(achievementTitle(context, a.id), textAlign: TextAlign.center, maxLines: 2, style: context.text.labelLarge),
          const SizedBox(height: Space.x1),
          if (!a.earned)
            ClipRRect(
              borderRadius: BorderRadius.circular(Radii.pill),
              child: LinearProgressIndicator(value: a.progress, minHeight: 4, backgroundColor: c.outline, color: c.primary),
            ),
          const SizedBox(height: 2),
          Text(sub, style: context.text.labelSmall?.copyWith(color: c.text2)),
        ]),
      ),
    );
  }
}

/// Строка истории: квест, организация, дата, часы и Tz.
class CreditTile extends StatelessWidget {
  const CreditTile({super.key, required this.credit, this.pending = false});
  final Credit credit;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final cr = credit;
    final d = cr.date;
    final date = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    final bonus = cr.kind == CreditKind.seniorBonus;
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x2),
        child: Row(children: [
          Icon(pending ? Icons.hourglass_top_rounded : (bonus ? Icons.shield_rounded : Icons.verified_rounded), color: pending ? c.warning : c.primaryStrong),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(bonus ? l.seniorBonusLabel : cr.questTitle, style: context.text.titleSmall),
              Text(
                [date, if (bonus) cr.questTitle else if (cr.orgName.isNotEmpty) cr.orgName, if (pending) l.awaitingCoordinator].join(' · '),
                style: context.text.bodySmall?.copyWith(color: c.text2),
              ),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            if (cr.hours > 0) Text(formatHours(context, cr.hours), style: context.text.titleSmall),
            Text('+${cr.tz} Tz', style: context.text.labelMedium?.copyWith(color: c.primaryStrong, fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
    );
  }
}
