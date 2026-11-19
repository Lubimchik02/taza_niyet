import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_x.dart';
import '../org/org_controller.dart';
import '../people/people_controller.dart';
import '../quests/quests_controller.dart';
import '../shift/shift_controller.dart';
import '../shift/widgets/hours_format.dart';

enum FeedKind { friendShift, newQuest, achievement, mine }

@immutable
class FeedItem {
  const FeedItem({required this.kind, required this.at, this.name = '', this.quest = '', this.org = '', this.hours = 0, this.route});
  final FeedKind kind;
  final DateTime at;
  final String name, quest, org;
  final double hours;
  final String? route;
}

/// Лента: мои начисления, смены и достижения друзей, новые квесты своей организации.
/// В реальном приложении — серверная выборка «события друзей + организации» (этап 12).
final feedProvider = Provider<List<FeedItem>>((ref) {
  final now = DateTime.now();
  final friends = ref.watch(friendPeopleProvider);
  final m = ref.watch(membershipProvider);
  final quests = ref.watch(questsProvider).valueOrNull ?? const [];
  final items = <FeedItem>[
    for (final c in ref.watch(creditsProvider).where((c) => c.kind == CreditKind.shift))
      FeedItem(kind: FeedKind.mine, at: c.date.isAfter(now) ? now : c.date, quest: c.questTitle, hours: c.hours),
    for (final (i, f) in friends.indexed) ...[
      FeedItem(kind: FeedKind.friendShift, at: now.subtract(Duration(hours: 2 + i * 20)), name: f.name, quest: i.isEven ? 'Посадка деревьев в парке' : 'Уборка набережной Ишима', hours: i.isEven ? 6 : 3, route: '/people/${f.id}'),
      if (i == 0) FeedItem(kind: FeedKind.achievement, at: now.subtract(const Duration(days: 3)), name: f.name, route: '/people/${f.id}'),
    ],
    if (m != null)
      for (final q in quests.where((q) => q.orgId == m.orgId).take(1))
        FeedItem(kind: FeedKind.newQuest, at: now.subtract(const Duration(hours: 5)), org: m.orgName, quest: q.title, route: '/quest/${q.id}'),
  ]..sort((a, b) => b.at.compareTo(a.at));
  return items.take(6).toList();
});

String feedText(BuildContext context, FeedItem f) {
  final l = context.l;
  return switch (f.kind) {
    FeedKind.mine => l.feedMine(formatHours(context, f.hours), f.quest),
    FeedKind.friendShift => l.feedShift(f.name, formatHours(context, f.hours), f.quest),
    FeedKind.newQuest => l.feedNewQuest(f.org, f.quest),
    FeedKind.achievement => l.feedAchievement(f.name, l.achH10),
  };
}

IconData feedIcon(FeedKind k) => switch (k) {
      FeedKind.mine => Icons.workspace_premium_rounded,
      FeedKind.friendShift => Icons.eco_rounded,
      FeedKind.newQuest => Icons.campaign_rounded,
      FeedKind.achievement => Icons.emoji_events_rounded,
    };

String timeAgo(BuildContext context, DateTime t) {
  final l = context.l;
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 60) return l.agoMin(d.inMinutes.clamp(1, 59));
  if (d.inHours < 24) return l.agoHours(d.inHours);
  return l.agoDays(d.inDays);
}
