import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_x.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/haptics.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../chats/chats_controller.dart';
import '../chats/data/chat_repository.dart';
import '../profile/widgets/profile_widgets.dart';
import 'data/people_repository.dart';
import 'people_controller.dart';
import 'people_widgets.dart';

/// Профиль другого волонтёра: часы без лишних шагов (если он их не скрыл), достижения,
/// дружба, написать, пожаловаться/заблокировать.
class PersonScreen extends ConsumerWidget {
  const PersonScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return ref.watch(personProvider(id)).when(
          loading: () => Scaffold(appBar: AppBar(), body: ListView(padding: const EdgeInsets.all(Space.screen), children: const [SkeletonListTile(), SkeletonListTile()])),
          error: (_, __) => Scaffold(appBar: AppBar(), body: ErrorState(title: l.errorNetworkTitle, body: l.errorNetworkBody, retryLabel: l.retry, onRetry: () => ref.invalidate(personProvider(id)))),
          data: (p) => p == null ? Scaffold(appBar: AppBar(), body: EmptyState(title: l.noResults(''), body: '')) : _Body(p),
        );
  }
}

class _Body extends ConsumerWidget {
  const _Body(this.p);
  final Person p;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final c = context.colors;
    final fr = ref.watch(friendsProvider);
    final isFriend = fr.friends.contains(p.id);
    final sent = fr.outgoing.contains(p.id);
    final incoming = fr.incoming.contains(p.id);
    final visible = canSeeHours(p, isFriend: isFriend);
    final ctrl = ref.read(friendsProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);

    Future<void> add() async {
      Haptics.play(HapticKind.medium);
      final ok = await ctrl.request(p.id);
      if (ok) messenger.showSnackBar(SnackBar(content: Text(l.friendAdded(p.name))));
    }

    return Scaffold(
      appBar: AppBar(actions: [
        PopupMenuButton<String>(
          onSelected: (v) async {
            switch (v) {
              case 'remove':
                ctrl.remove(p.id);
              case 'report':
                await ref.read(chatStoreProvider.notifier).report(chatId: 'profile', userId: p.id, reason: ReportReason.other);
                messenger.showSnackBar(SnackBar(content: Text(l.reportSent)));
              case 'block':
                await ref.read(chatStoreProvider.notifier).setBlocked(p.id, true);
                ctrl.remove(p.id);
                if (context.mounted) context.pop();
            }
          },
          itemBuilder: (_) => [
            if (isFriend) PopupMenuItem(value: 'remove', child: Text(l.removeFriend)),
            PopupMenuItem(value: 'report', child: Text(l.reportAction)),
            PopupMenuItem(value: 'block', child: Text(l.blockAction)),
          ],
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.x8), children: [
        Row(children: [
          PersonAvatar(name: p.name, size: 64),
          const SizedBox(width: Space.x4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.name, style: context.text.headlineSmall),
              Text([p.orgName, if (isFriend) l.friendsLabel].join(' · '), style: context.text.bodyMedium?.copyWith(color: c.text2)),
            ]),
          ),
        ]),
        const SizedBox(height: Space.x4),
        if (visible)
          StatsRow(hours: p.hours, tz: p.tz, shifts: p.shifts)
        else
          Container(
            padding: const EdgeInsets.all(Space.x4),
            decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Radii.md)),
            child: Row(children: [
              Icon(Icons.lock_outline_rounded, color: c.text2),
              const SizedBox(width: Space.x3),
              Expanded(child: Text(p.minor ? l.minorProfileNote : l.hoursHidden, style: context.text.bodyMedium)),
            ]),
          ),
        const SizedBox(height: Space.x4),
        if (incoming)
          Row(children: [
            Expanded(child: AppButton(label: l.acceptAction, onPressed: () => ctrl.accept(p.id))),
            const SizedBox(width: Space.x2),
            Expanded(child: AppButton(label: l.declineAction, kind: AppButtonKind.ghost, onPressed: () => ctrl.decline(p.id))),
          ])
        else if (isFriend)
          AppButton(label: l.writeMessage, icon: Icons.chat_bubble_outline_rounded, kind: AppButtonKind.secondary, onPressed: () => context.push('/chat/dm-${p.id}'))
        else if (sent)
          AppButton(label: l.requestSent, kind: AppButtonKind.secondary, onPressed: () => ctrl.cancel(p.id))
        else
          AppButton(label: l.addFriend, icon: Icons.person_add_alt_rounded, onPressed: add),
        if (visible && p.achievements.isNotEmpty) ...[
          const SizedBox(height: Space.x6),
          Semantics(header: true, child: Text(l.achievementsTitle, style: context.text.titleLarge)),
          const SizedBox(height: Space.x2),
          Wrap(spacing: Space.x2, runSpacing: Space.x2, children: [
            for (final a in p.achievements)
              Chip(avatar: Icon(achievementIcon(a), size: 18, color: c.primaryStrong), label: Text(achievementTitle(context, a)), backgroundColor: c.lime, side: BorderSide.none),
          ]),
        ],
      ]),
    );
  }
}

