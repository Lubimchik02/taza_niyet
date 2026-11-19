import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_x.dart';
import '../../core/router/app_router.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/skeleton.dart';
import '../org/data/org_repository.dart';
import '../org/org_controller.dart';
import '../quests/signups_controller.dart';
import '../quests/widgets/quest_card.dart';
import '../shift/shift_controller.dart';
import '../shift/widgets/hours_format.dart';
import '../people/data/people_repository.dart';
import '../people/people_controller.dart';
import '../people/people_widgets.dart';
import 'feed.dart';
import '../../core/config/app_config.dart';
import '../notifications/notifications.dart';

/// «Позже» на карточке организации — прячем до следующего запуска, не навсегда.
final orgNudgeHiddenProvider = StateProvider<bool>((ref) => false);

/// Главная: поиск волонтёров, мягкий вход (инструкция → организация), заявки в друзья,
/// мои записи, рейтинг месяца (упрощённый: топ-3 и я) и лента новостей.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final c = context.colors;
    final guideSeen = ref.watch(settingsProvider.select((s) => s.guideSeen));
    final m = ref.watch(membershipProvider);
    final nudgeHidden = ref.watch(orgNudgeHiddenProvider);
    final mine = ref.watch(mySignupsProvider);
    final totals = ref.watch(totalsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          header: true,
          // Название приложения не переводится.
          child: Text('Taza Niyet', style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
        ),
        actions: [
          IconButton(
            tooltip: l.notifCenter,
            onPressed: () => context.push('/notifications'),
            icon: Badge(
              isLabelVisible: ref.watch(unreadNotificationsProvider) > 0,
              label: Text('${ref.watch(unreadNotificationsProvider)}'),
              child: const Icon(Icons.notifications_none_rounded),
            ),
          ),
          // Иконка-решётка «#»: инструкция «Как это работает». Точка — пока не прочитана.
          IconButton(
            tooltip: l.guideIcon,
            onPressed: () => context.push(Routes.guide),
            icon: Badge(isLabelVisible: !guideSeen, backgroundColor: c.primary, smallSize: 9, child: const Icon(Icons.tag_rounded)),
          ),
          const SizedBox(width: Space.x2),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(Space.screen), children: [
        // Поиск волонтёров — часы друга видны прямо в результатах.
        Semantics(
          button: true,
          label: l.searchPeople,
          child: Material(
            color: c.surface2,
            borderRadius: BorderRadius.circular(Radii.sm),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.sm),
              onTap: () => context.push('/people'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
                child: Row(children: [
                  Icon(Icons.search_rounded, color: c.text2),
                  const SizedBox(width: Space.x3),
                  Text(l.searchPeople, style: context.text.bodyLarge?.copyWith(color: c.text2)),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: Space.x4),
        const _FriendRequests(),
        // Итог подтверждённых часов (подробно — в портфолио, этап 8).
        if (totals.tz > 0)
          _Nudge(icon: Icons.workspace_premium_rounded, title: l.myHours, body: l.hoursTotal(formatHours(context, totals.hours), totals.tz), highlight: true),
        if (!guideSeen)
          _Nudge(
            icon: Icons.tag_rounded,
            title: l.guideCardT,
            body: l.guideCardB,
            highlight: true,
            onTap: () => context.push(Routes.guide),
          )
        else if (m == null && !nudgeHidden)
          _Nudge(
            icon: Icons.groups_2_rounded,
            title: l.orgTitle,
            body: l.orgCardB,
            actions: [
              Expanded(child: AppButton(label: l.choose, onPressed: () => context.push(Routes.org))),
              const SizedBox(width: Space.x2),
              Expanded(
                child: AppButton(
                  label: l.later,
                  kind: AppButtonKind.ghost,
                  onPressed: () => ref.read(orgNudgeHiddenProvider.notifier).state = true,
                ),
              ),
            ],
          ),
        if (m?.status == MembershipStatus.pending)
          _Nudge(icon: Icons.hourglass_top_rounded, title: l.pendingTitle, body: l.orgPendingBanner(m!.orgName), onTap: () => context.push(Routes.orgPending)),
        if (m?.status == MembershipStatus.rejected)
          _Nudge(
            icon: Icons.info_outline_rounded,
            title: l.rejectedTitle,
            body: l.rejectedBody(m!.orgName),
            actions: [Expanded(child: AppButton(label: l.choose, onPressed: () => context.push(Routes.org)))],
          ),
        if (mine.isNotEmpty) ...[
          const SizedBox(height: Space.x3),
          Semantics(header: true, child: Text(l.mySignups, style: context.text.titleLarge)),
          const SizedBox(height: Space.x3),
          for (final s in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.x3),
              child: QuestCard(quest: s.quest, statusLabel: signupLabel(l, s), onTap: () => context.push('/quest/${s.quest.id}')),
            ),
        ] else ...[
          const SizedBox(height: Space.x6),
          // Пока нет записей — ведём на карту (без организации там все квесты города, только просмотр).
          Icon(Icons.eco_rounded, size: 48, color: c.primary),
          const SizedBox(height: Space.x3),
          Text(l.emptyQuestsTitle, style: context.text.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: Space.x1),
          Text(l.emptyQuestsBody, style: context.text.bodyMedium?.copyWith(color: c.text2), textAlign: TextAlign.center),
          const SizedBox(height: Space.x4),
          Center(child: AppButton(label: l.findQuest, kind: AppButtonKind.secondary, expand: false, onPressed: () => context.go(Routes.map))),
        ],
        // Рейтинг и ленту можно выключить удалённо (feature flags), не выпуская новую версию.
        if (ref.watch(flagProvider(Flags.rating))) const _RatingBlock(),
        if (ref.watch(flagProvider(Flags.feed))) const _FeedBlock(),
      ]),
    );
  }
}

/// Мягкая карточка-подсказка: не модалка, не блокирует, закрывается «Позже».
class _Nudge extends StatelessWidget {
  const _Nudge({required this.icon, required this.title, required this.body, this.onTap, this.actions, this.highlight = false});

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onTap;
  final List<Widget>? actions;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: highlight ? c.primary : c.lime, borderRadius: BorderRadius.circular(Radii.sm)),
          child: Icon(icon, color: highlight ? c.onPrimary : c.primaryStrong),
        ),
        const SizedBox(width: Space.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: context.text.titleMedium),
            const SizedBox(height: Space.x1),
            Text(body, style: context.text.bodyMedium?.copyWith(color: c.text2)),
          ]),
        ),
        if (onTap != null) Icon(Icons.chevron_right_rounded, color: c.text2),
      ]),
      if (actions != null) ...[const SizedBox(height: Space.x3), Row(children: actions!)],
    ]);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: AppCard(onTap: onTap, child: content),
    );
  }
}

class _FriendRequests extends ConsumerWidget {
  const _FriendRequests();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final ids = ref.watch(friendsProvider).incoming;
    if (ids.isEmpty) return const SizedBox.shrink();
    final repo = ref.read(peopleRepositoryProvider);
    final people = ids.map(repo.cached).whereType<Person>();
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x3),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.friendRequestsT, style: context.text.titleMedium),
          for (final p in people)
            Padding(
              padding: const EdgeInsets.only(top: Space.x3),
              child: Row(children: [
                InkWell(onTap: () => context.push('/people/${p.id}'), child: PersonAvatar(name: p.name)),
                const SizedBox(width: Space.x3),
                Expanded(child: Text(p.name, style: context.text.titleSmall)),
                TextButton(onPressed: () => ref.read(friendsProvider.notifier).decline(p.id), child: Text(l.declineAction)),
                FilledButton(onPressed: () => ref.read(friendsProvider.notifier).accept(p.id), child: Text(l.acceptAction)),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Упрощённый рейтинг: топ-3 + моя строка (если я ниже). Полный — на отдельном экране.
class _RatingBlock extends ConsumerWidget {
  const _RatingBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final c = context.colors;
    final scope = ref.watch(ratingScopeProvider);
    final rating = ref.watch(ratingProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: Space.x6),
      Row(children: [
        Expanded(child: Semantics(header: true, child: Text(l.ratingTitle, style: context.text.titleLarge))),
        TextButton(onPressed: () => context.push('/rating'), child: Text(l.ratingAll)),
      ]),
      const SizedBox(height: Space.x2),
      SegmentedButton<RatingScope>(
        showSelectedIcon: false,
        segments: [ButtonSegment(value: RatingScope.org, label: Text(l.ratingOrg)), ButtonSegment(value: RatingScope.city, label: Text(l.ratingCity))],
        selected: {scope},
        onSelectionChanged: (v) => ref.read(ratingScopeProvider.notifier).state = v.first,
      ),
      const SizedBox(height: Space.x2),
      rating.when(
        loading: () => const SkeletonListTile(),
        error: (_, __) => Text(l.errorNetworkBody),
        data: (rows) {
          if (rows == null) return Padding(padding: const EdgeInsets.all(Space.x3), child: Text(l.ratingEmpty, style: context.text.bodyMedium?.copyWith(color: c.text2)));
          final me = rows.firstWhere((r) => r.isMe);
          final shown = [...rows.take(3), if (!rows.take(3).contains(me)) me];
          return AppCard(
            padding: const EdgeInsets.all(Space.x2),
            child: Column(children: [
              for (final r in shown)
                RatingTile(row: r, formatted: formatHours(context, r.monthHours), onTap: () => context.push('/people/${r.id}')),
              Padding(
                padding: const EdgeInsets.all(Space.x2),
                child: Text(l.ratingPlace(me.place), style: context.text.labelLarge?.copyWith(color: c.primaryStrong)),
              ),
            ]),
          );
        },
      ),
    ]);
  }
}

class _FeedBlock extends ConsumerWidget {
  const _FeedBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final c = context.colors;
    final items = ref.watch(feedProvider);
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: Space.x6),
      Semantics(header: true, child: Text(l.feedTitle, style: context.text.titleLarge)),
      const SizedBox(height: Space.x2),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: Space.x2, vertical: Space.x1),
        child: Column(children: [
          for (final f in items)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.x2),
              leading: CircleAvatar(backgroundColor: c.lime, child: Icon(feedIcon(f.kind), color: c.primaryStrong)),
              title: Text(feedText(context, f), style: context.text.bodyMedium),
              subtitle: Text(timeAgo(context, f.at), style: context.text.labelSmall?.copyWith(color: c.text2)),
              onTap: f.route == null ? null : () => context.push(f.route!),
            ),
        ]),
      ),
    ]);
  }
}
