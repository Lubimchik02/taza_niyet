import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_x.dart';
import '../../core/ui/haptics.dart';
import '../../core/config/app_config.dart';
import '../../core/net/connectivity.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../chats/chats_controller.dart';
import '../notifications/notifications.dart';
import '../notifications/push_service.dart';
import '../offline/sync.dart';
import 'package:url_launcher/url_launcher.dart';
import '../org/data/org_repository.dart';
import '../org/org_controller.dart';

/// Нижняя панель: Главная · Карта · Чаты · Профиль.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    // Координатор ответил, пока человек пользуется приложением.
    ref.listen(membershipProvider, (prev, next) {
      if (prev?.status == MembershipStatus.pending && next?.status == MembershipStatus.active) {
        Haptics.play(HapticKind.success);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.approvedToast(next!.orgName))));
        ref.read(inboxProvider.notifier).add(kind: NotifKind.org, title: l.approvedToast(next.orgName), route: '/map');
      }
    });
    // Сеть вернулась — отправляем очередь (отметки «Я на месте», сообщения).
    ref.listen(isOnlineProvider, (prev, online) async {
      if (prev == false && online) {
        final messenger = ScaffoldMessenger.of(context);
        final n = await flushOutbox(ref);
        if (n > 0) messenger.showSnackBar(SnackBar(content: Text(l.syncDone)));
      }
    });
    PushService.start(GoRouter.of(context)); // один раз после входа; без Firebase — ничего не делает
    final online = ref.watch(isOnlineProvider);
    final soft = ref.watch(updateStatusProvider) == UpdateStatus.available && !ref.watch(softUpdateDismissedProvider);
    final chatsOn = ref.watch(flagProvider(Flags.chats));
    ref.watch(chatPreloadProvider);
    final unread = ref.watch(totalUnreadProvider);
    final c = context.colors;
    return Scaffold(
      body: Column(children: [
        if (!online)
          Semantics(
            liveRegion: true,
            child: Container(
              width: double.infinity,
              color: c.text,
              padding: EdgeInsets.fromLTRB(Space.x4, MediaQuery.paddingOf(context).top + Space.x2, Space.x4, Space.x2),
              child: Row(children: [
                Icon(Icons.cloud_off_rounded, size: 18, color: c.bg),
                const SizedBox(width: Space.x2),
                Expanded(child: Text(l.cachedData, style: context.text.bodyMedium?.copyWith(color: c.bg))),
              ]),
            ),
          )
        else if (soft)
          Material(
            color: c.lime,
            child: Padding(
              padding: EdgeInsets.fromLTRB(Space.x4, MediaQuery.paddingOf(context).top, Space.x1, 0),
              child: Row(children: [
                Icon(Icons.system_update_rounded, color: c.primaryStrong),
                const SizedBox(width: Space.x2),
                Expanded(child: Text(l.updateSoft, style: context.text.bodyMedium)),
                TextButton(onPressed: () => launchUrl(Uri.parse(ref.read(appConfigProvider).storeUrl), mode: LaunchMode.externalApplication), child: Text(l.updateAction)),
                IconButton(tooltip: l.later, onPressed: () => ref.read(softUpdateDismissedProvider.notifier).state = true, icon: const Icon(Icons.close_rounded)),
              ]),
            ),
          ),
        Expanded(child: online && !soft ? shell : MediaQuery.removePadding(context: context, removeTop: true, child: shell)),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) {
          Haptics.play(HapticKind.light);
          // Повторное нажатие на активную вкладку возвращает к её началу.
          shell.goBranch(i, initialLocation: i == shell.currentIndex);
        },
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home_rounded), label: l.tabHome),
          NavigationDestination(icon: const Icon(Icons.map_outlined), selectedIcon: const Icon(Icons.map_rounded), label: l.tabMap),
          NavigationDestination(
            enabled: chatsOn,
            icon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.chat_bubble_outline_rounded)),
            selectedIcon: Badge(isLabelVisible: unread > 0, label: Text('$unread'), child: const Icon(Icons.chat_bubble_rounded)),
            label: l.tabChats,
          ),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), selectedIcon: const Icon(Icons.person_rounded), label: l.tabProfile),
        ],
      ),
    );
  }
}
