import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_x.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/state_views.dart';
import '../home/feed.dart';
import 'notifications.dart';

/// Входящие уведомления: непрочитанные выделены, нажатие открывает нужный экран.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final c = context.colors;
    final list = ref.watch(inboxProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.notifCenter), actions: [
        if (list.any((n) => !n.read)) TextButton(onPressed: () => ref.read(inboxProvider.notifier).readAll(), child: Text(l.markAllRead)),
      ]),
      body: list.isEmpty
          ? EmptyState(title: l.notifEmptyT, body: l.notifEmptyB)
          : ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: c.outline),
              itemBuilder: (_, i) {
                final n = list[i];
                final icon = switch (n.kind) {
                  NotifKind.reminder => Icons.alarm_rounded,
                  NotifKind.hoursApproved => Icons.workspace_premium_rounded,
                  NotifKind.friend => Icons.person_add_alt_rounded,
                  NotifKind.org => Icons.verified_rounded,
                  NotifKind.chat => Icons.chat_bubble_outline_rounded,
                  NotifKind.system => Icons.info_outline_rounded,
                };
                final title = switch (n.kind) {
                  NotifKind.hoursApproved => l.nfApprovedT(int.tryParse(n.args['tz'] ?? '') ?? 0),
                  NotifKind.friend when n.args['kind'] == 'friend_request' => '${l.friendRequestsT}: ${n.args['name'] ?? ''}',
                  NotifKind.friend => l.friendAdded(n.args['name'] ?? ''),
                  NotifKind.org when n.args['kind'] == 'org_rejected' => l.rejectedTitle,
                  NotifKind.org when n.title.isEmpty || n.args.containsKey('org') => l.approvedToast(n.args['org'] ?? n.title),
                  NotifKind.reminder => l.nfReminderHour(n.args['quest'] ?? ''),
                  _ => n.title,
                };
                return Material(
                  color: n.read ? Colors.transparent : c.lime.withValues(alpha: .5),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: c.lime, child: Icon(icon, color: c.primaryStrong)),
                    title: Text(title, style: n.read ? null : const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text([if (n.body.isNotEmpty) n.body, timeAgo(context, n.at)].join('\n')),
                    isThreeLine: n.body.isNotEmpty,
                    onTap: () {
                      ref.read(inboxProvider.notifier).read(n.id);
                      if (n.route != null) context.push(n.route!);
                    },
                  ),
                );
              },
            ),
    );
  }
}
