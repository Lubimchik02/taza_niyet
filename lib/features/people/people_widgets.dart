import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_x.dart';
import '../../core/theme/app_theme.dart';
import '../org/org_controller.dart';
import '../shift/shift_controller.dart';
import 'data/people_repository.dart';
import 'people_controller.dart';

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.name, this.size = 44, this.highlight = false});
  final String name;
  final double size;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: size / 2,
        backgroundColor: highlight ? c.primary : c.lime,
        child: Text(name.isEmpty ? '?' : name.characters.first, style: context.text.titleMedium?.copyWith(color: highlight ? c.onPrimary : c.primaryStrong, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

/// Мои подтверждённые часы за текущий месяц.
final myMonthHoursProvider = Provider<double>((ref) {
  final now = DateTime.now();
  return ref.watch(creditsProvider).where((c) => c.date.year == now.year && c.date.month == now.month).fold(0.0, (a, c) => a + c.hours);
});

final ratingScopeProvider = StateProvider<RatingScope>((ref) => RatingScope.org);

/// Рейтинг месяца для текущего пользователя (null — нет организации и выбран рейтинг организации).
final ratingProvider = Provider<AsyncValue<List<RatingRow>?>>((ref) {
  final scope = ref.watch(ratingScopeProvider);
  final m = ref.watch(membershipProvider);
  final friends = ref.watch(friendsProvider).friends;
  final myH = ref.watch(myMonthHoursProvider);
  return ref.watch(allPeopleProvider).whenData((people) {
    if (scope == RatingScope.org && m == null) return null;
    return buildRating(people, scope: scope, myOrg: m?.orgName ?? '', myCity: 'astana', myMonthHours: myH, myName: '', friends: friends); // имя «Вы» подставляет экран
  });
});

/// Строка рейтинга: место, аватар, имя, часы за месяц. Моя строка подсвечена.
class RatingTile extends StatelessWidget {
  const RatingTile({super.key, required this.row, required this.formatted, this.onTap});
  final RatingRow row;
  final String formatted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final medal = switch (row.place) { 1 => const Color(0xFFE8B931), 2 => const Color(0xFFB8C0C8), 3 => const Color(0xFFCD8B4E), _ => null };
    final name = row.isMe ? l.youLabel : row.name;
    return Material(
      color: row.isMe ? c.lime : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: row.isMe ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            SizedBox(
              width: 32,
              child: medal != null
                  ? Icon(Icons.emoji_events_rounded, color: medal, semanticLabel: '${row.place}')
                  : Text('${row.place}', textAlign: TextAlign.center, style: context.text.titleSmall?.copyWith(color: c.text2)),
            ),
            const SizedBox(width: 8),
            PersonAvatar(name: name, size: 36, highlight: row.isMe),
            const SizedBox(width: 12),
            Expanded(child: Text(name, style: context.text.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            Text(formatted, style: context.text.titleSmall?.copyWith(color: c.primaryStrong)),
          ]),
        ),
      ),
    );
  }
}
