import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/l10n_x.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/state_views.dart';
import 'chats_controller.dart';
import 'data/chat_repository.dart';

/// Список чатов как в мессенджере: аватар, имя, последнее сообщение, время, непрочитанные.
class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final st = ref.watch(chatStoreProvider);
    final q = _q.trim().toLowerCase();
    final chats = ref.watch(chatsProvider).where((c) => q.isEmpty || c.title.toLowerCase().contains(q)).toList()
      ..sort((a, b) {
        final ta = lastVisible(st, a.id)?.sentAt, tb = lastVisible(st, b.id)?.sentAt;
        if (ta == null || tb == null) return ta == null ? 1 : -1;
        return tb.compareTo(ta);
      });

    if (!ref.watch(flagProvider(Flags.chats))) {
      return Scaffold(appBar: AppBar(title: Text(l.tabChats)), body: EmptyState(title: l.featureOff, body: ''));
    }
    return Scaffold(
      appBar: AppBar(title: Text(l.tabChats)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.x2),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search_rounded), hintText: l.chatSearch),
          ),
        ),
        Expanded(
          child: chats.isEmpty
              ? (q.isEmpty ? EmptyState(title: l.emptyChatsTitle, body: l.emptyChatsBody) : EmptyState(title: l.noResults(_q.trim()), body: ''))
              : ListView.builder(itemCount: chats.length, itemBuilder: (_, i) => _ChatTile(chat: chats[i])),
        ),
      ]),
    );
  }
}

/// «12:40», «Вчера», «18.11».
String chatTime(BuildContext context, DateTime t) {
  final now = DateTime.now();
  final d = DateTime(t.year, t.month, t.day), today = DateTime(now.year, now.month, now.day);
  if (d == today) return TimeOfDay.fromDateTime(t).format(context);
  if (today.difference(d).inDays == 1) return context.l.yesterdayLabel;
  return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}';
}

class ChatAvatar extends StatelessWidget {
  const ChatAvatar({super.key, required this.chat, this.size = 52});
  final Chat chat;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final icon = switch (chat.kind) { ChatKind.channel => Icons.campaign_rounded, ChatKind.team => Icons.groups_2_rounded, ChatKind.direct => null };
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: chat.kind == ChatKind.direct ? c.lime : c.primary, shape: BoxShape.circle),
        child: icon != null
            ? Icon(icon, color: c.onPrimary, size: size * .5)
            : Text(chat.title.characters.first, style: context.text.titleLarge?.copyWith(color: c.primaryStrong, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _ChatTile extends ConsumerWidget {
  const _ChatTile({required this.chat});
  final Chat chat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final c = context.colors;
    final st = ref.watch(chatStoreProvider);
    final last = lastVisible(st, chat.id);
    final unread = unreadIn(st, chat.id);
    final muted = st.muted.contains(chat.id);
    final kind = switch (chat.kind) {
      ChatKind.channel => l.channelLabel,
      ChatKind.team => l.teamChatLabel(chat.subtitle ?? ''),
      ChatKind.direct => l.directLabel,
    };
    final preview = last == null ? (chat.kind == ChatKind.direct ? l.friendsLabel : l.systemAdded) : (last.mine ? l.youPrefix(last.text) : (chat.kind == ChatKind.direct ? last.text : '${last.authorName}: ${last.text}'));
    return InkWell(
      onTap: () => context.push('/chat/${chat.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.screen, vertical: Space.x3),
        child: Row(children: [
          ChatAvatar(chat: chat),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium)),
                if (muted) Padding(padding: const EdgeInsets.only(left: Space.x1), child: Icon(Icons.notifications_off_outlined, size: 16, color: c.text2)),
                if (last != null) Padding(padding: const EdgeInsets.only(left: Space.x2), child: Text(chatTime(context, last.sentAt), style: context.text.labelSmall?.copyWith(color: c.text2))),
              ]),
              Text(kind, style: context.text.labelSmall?.copyWith(color: c.primaryStrong)),
              const SizedBox(height: 2),
              Row(children: [
                Expanded(child: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium?.copyWith(color: c.text2))),
                if (unread > 0)
                  Container(
                    margin: const EdgeInsets.only(left: Space.x2),
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    constraints: const BoxConstraints(minWidth: 22),
                    decoration: BoxDecoration(color: muted ? c.outline : c.primary, borderRadius: BorderRadius.circular(Radii.pill)),
                    child: Text('$unread', textAlign: TextAlign.center, style: context.text.labelSmall?.copyWith(color: c.onPrimary, fontWeight: FontWeight.w800)),
                  ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
