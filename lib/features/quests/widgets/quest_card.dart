import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/geo.dart';
import '../../../core/l10n_x.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_card.dart';
import '../../../l10n/app_localizations.dart';
import '../data/quest_repository.dart';
import '../data/signup_repository.dart';

String difficultyLabel(AppLocalizations l, Difficulty d) => switch (d) {
      Difficulty.easy => l.diffEasy,
      Difficulty.medium => l.diffMedium,
      Difficulty.hard => l.diffHard,
    };

/// «Сб, 21 ноя · 10:00» на языке пользователя.
String questWhen(BuildContext context, DateTime t) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return '${DateFormat.MMMEd(locale).format(t)} · ${DateFormat.Hm(locale).format(t)}';
}

/// Сложность точками (●●○) + словом — смысл не только цветом.
class DifficultyDots extends StatelessWidget {
  const DifficultyDots(this.d, {super.key});
  final Difficulty d;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final n = d.index + 1;
    return Semantics(
      label: difficultyLabel(context.l, d),
      excludeSemantics: true,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 3),
            decoration: BoxDecoration(shape: BoxShape.circle, color: i < n ? c.primaryStrong : c.outline),
          ),
        const SizedBox(width: Space.x1),
        Text(difficultyLabel(context.l, d), style: context.text.labelSmall?.copyWith(color: c.text2)),
      ]),
    );
  }
}

/// Подпись статуса моей записи для карточки квеста.
String? signupLabel(AppLocalizations l, Signup? s) => switch (s) {
      null => null,
      Signup(status: SignupStatus.waitlist) => l.waitlistChip(s.position),
      Signup(shift: ShiftState.approved) => '+${(s.hours * 5).round()} Tz', // 1 ч = 5 Tz
      _ => l.youJoined,
    };

class QuestCard extends StatelessWidget {
  const QuestCard({super.key, required this.quest, this.km, required this.onTap, this.statusLabel});

  final Quest quest;

  /// «Вы записаны» / «Лист ожидания №3» — вместо счётчика мест.
  final String? statusLabel;
  final double? km;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final lang = Localizations.localeOf(context).languageCode;
    final q = quest;
    return AppCard(
      onTap: onTap,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(q.title, style: context.text.titleMedium)),
          const SizedBox(width: Space.x2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x1),
            decoration: BoxDecoration(color: c.tzBg, borderRadius: BorderRadius.circular(Radii.pill)),
            child: Text(l.upToTz(q.maxTz), style: context.text.labelSmall?.copyWith(color: c.tzFg)),
          ),
        ]),
        const SizedBox(height: Space.x1),
        Text(
          [questWhen(context, q.startsAt), l.hoursShort(q.duration.inHours), if (km != null) l.kmAway(formatKm(km!, lang))].join(' · '),
          style: context.text.bodyMedium?.copyWith(color: c.text2),
        ),
        const SizedBox(height: Space.x2),
        Row(children: [
          DifficultyDots(q.difficulty),
          const Spacer(),
          if (statusLabel != null) ...[
            Icon(Icons.check_circle_rounded, size: 16, color: c.primaryStrong),
            const SizedBox(width: Space.x1),
            Text(statusLabel!, style: context.text.labelSmall?.copyWith(color: c.primaryStrong, fontWeight: FontWeight.w700)),
          ] else ...[
            Icon(q.isFull ? Icons.hourglass_top_rounded : Icons.group_outlined, size: 16, color: q.isFull ? c.warning : c.text2),
            const SizedBox(width: Space.x1),
            Text(
              q.isFull ? l.questFull : l.spotsLeft(q.spotsLeft, q.capacity),
              style: context.text.labelSmall?.copyWith(color: q.isFull ? c.warning : c.text2),
            ),
          ],
        ]),
      ]),
    );
  }
}
