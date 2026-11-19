import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_x.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/haptics.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import 'chats_controller.dart';
import 'chats_screen.dart';
import 'data/chat_repository.dart';

/// Переписка: пузыри, разделители дней, статусы отправки, жалоба и блокировка
/// (обязательны для App Store и Google Play в приложениях с общением).
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.chatId});
  final String chatId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  Object? _error;

  Chat? get _chat => ref.read(chatsProvider).where((c) => c.id == widget.chatId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _input.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final chat = _chat;
    if (chat == null) return;
    setState(() => _error = null);
    try {
      await ref.read(chatStoreProvider.notifier).load(chat);
      ref.read(chatStoreProvider.notifier).markRead(chat.id);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _send(Chat chat) {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    Haptics.play(HapticKind.light);
    _input.clear();
    ref.read(chatStoreProvider.notifier).send(chat, text);
  }

  void _snack(String t) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t)));

  Future<void> _report(Chat chat, {Message? message}) async {
    final l = context.l;
    final reasons = {
      ReportReason.spam: l.reasonSpam,
      ReportReason.insult: l.reasonInsult,
      ReportReason.inappropriate: l.reasonInappropriate,
      ReportReason.danger: l.reasonDanger,
      ReportReason.other: l.reasonOther,
    };
    final r = await showModalBottomSheet<ReportReason>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x2), child: Text(l.reportT, style: ctx.text.titleLarge)),
          for (final e in reasons.entries) ListTile(title: Text(e.value), onTap: () => Navigator.pop(ctx, e.key)),
        ]),
      ),
    );
    if (r == null) return;
    await ref.read(chatStoreProvider.notifier).report(chatId: chat.id, messageId: message?.id, userId: message?.authorId ?? chat.peerId, reason: r);
    if (mounted) _snack(l.reportSent);
  }

  Future<void> _block(Chat chat, String userId, String name) async {
    final l = context.l;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l.blockT(name)),
        content: Text(l.blockB),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.keep)),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: ctx.colors.danger), child: Text(l.blockAction)),
        ],
      ),
    );
    if (ok == true) await ref.read(chatStoreProvider.notifier).setBlocked(userId, true);
  }

  Future<void> _messageMenu(Chat chat, Message m) async {
    final l = context.l;
    Haptics.play(HapticKind.medium);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.copy_rounded), title: Text(l.copyAction), onTap: () => Navigator.pop(ctx, 'copy')),
          if (!m.mine && m.role != AuthorRole.coordinator) ...[
            ListTile(leading: const Icon(Icons.flag_outlined), title: Text(l.reportAction), onTap: () => Navigator.pop(ctx, 'report')),
            ListTile(
              leading: Icon(Icons.block_rounded, color: ctx.colors.danger),
              title: Text(l.blockAction, style: TextStyle(color: ctx.colors.danger)),
              onTap: () => Navigator.pop(ctx, 'block'),
            ),
          ],
        ]),
      ),
    );
    if (!mounted) return;
    switch (action) {
      case 'copy':
        await Clipboard.setData(ClipboardData(text: m.text));
        _snack(l.copied);
      case 'report':
        await _report(chat, message: m);
      case 'block':
        await _block(chat, m.authorId, m.authorName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final chat = ref.watch(chatsProvider).where((x) => x.id == widget.chatId).firstOrNull;
    if (chat == null) {
      return Scaffold(appBar: AppBar(), body: EmptyState(title: l.emptyChatsTitle, body: l.emptyChatsBody));
    }
    final st = ref.watch(chatStoreProvider);
    // Новые сообщения в открытом чате сразу считаются прочитанными.
    ref.listen(chatStoreProvider.select((s) => s.messages[chat.id]?.length), (_, __) => ref.read(chatStoreProvider.notifier).markRead(chat.id));
    final all = st.messages[chat.id];
    final msgs = all?.where((m) => !st.blocked.contains(m.authorId)).toList();
    final muted = st.muted.contains(chat.id);
    final peerBlocked = chat.peerId != null && st.blocked.contains(chat.peerId);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          ChatAvatar(chat: chat, size: 40),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(chat.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleMedium),
              Text(
                switch (chat.kind) {
                  ChatKind.channel => l.channelLabel,
                  ChatKind.team => l.membersN(chat.members),
                  ChatKind.direct => l.directLabel,
                },
                style: context.text.labelSmall?.copyWith(color: c.text2),
              ),
            ]),
          ),
        ]),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'mute' => ref.read(chatStoreProvider.notifier).toggleMute(chat.id),
              'report' => _report(chat),
              'block' => _block(chat, chat.peerId!, chat.title),
              'unblock' => ref.read(chatStoreProvider.notifier).setBlocked(chat.peerId!, false),
              'quest' => context.push('/quest/${chat.questId}'),
              _ => null,
            },
            itemBuilder: (_) => [
              if (chat.questId != null) PopupMenuItem(value: 'quest', child: Text(l.openQuest)),
              PopupMenuItem(value: 'mute', child: Text(muted ? l.unmuteAction : l.muteAction)),
              if (chat.kind != ChatKind.channel) PopupMenuItem(value: 'report', child: Text(l.reportAction)),
              if (chat.peerId != null) PopupMenuItem(value: peerBlocked ? 'unblock' : 'block', child: Text(peerBlocked ? l.unblockAction : l.blockAction)),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: _error != null
              ? ErrorState(title: l.errorNetworkTitle, body: l.errorNetworkBody, retryLabel: l.retry, onRetry: _load)
              : msgs == null
                  ? ListView(padding: const EdgeInsets.all(Space.screen), children: const [SkeletonListTile(), SkeletonListTile()])
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x3),
                      itemCount: msgs.length + 1,
                      itemBuilder: (_, i) {
                        if (i == msgs.length) return _SafetyNote(text: l.chatSafetyNote);
                        final m = msgs[msgs.length - 1 - i];
                        final prev = msgs.length - 2 - i >= 0 ? msgs[msgs.length - 2 - i] : null;
                        final newDay = prev == null || !DateUtils.isSameDay(prev.sentAt, m.sentAt);
                        final showName = !m.mine && chat.kind != ChatKind.direct && (prev == null || prev.authorId != m.authorId || newDay);
                        return Column(children: [
                          if (newDay) _DayChip(date: m.sentAt),
                          if (m.role == AuthorRole.system)
                            _SystemLine(text: l.systemAdded)
                          else
                            _Bubble(
                              message: m,
                              showName: showName,
                              onLongPress: () => _messageMenu(chat, m),
                              onRetry: m.status == MessageStatus.failed ? () => ref.read(chatStoreProvider.notifier).send(chat, m.text, retry: m) : null,
                            ),
                        ]);
                      },
                    ),
        ),
        _Composer(
          chat: chat,
          controller: _input,
          blocked: peerBlocked,
          onSend: () => _send(chat),
          onUnblock: () => ref.read(chatStoreProvider.notifier).setBlocked(chat.peerId!, false),
        ),
      ]),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.chat, required this.controller, required this.blocked, required this.onSend, required this.onUnblock});
  final Chat chat;
  final TextEditingController controller;
  final bool blocked;
  final VoidCallback onSend, onUnblock;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    Widget note(String text, [Widget? action]) => Container(
          width: double.infinity,
          color: c.surface2,
          padding: const EdgeInsets.all(Space.x4),
          child: SafeArea(
            top: false,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(text, textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(color: c.text2)),
              if (action != null) action,
            ]),
          ),
        );
    if (chat.readOnly) return note(l.readOnlyNote);
    if (blocked) return note(l.blockedNote, TextButton(onPressed: onUnblock, child: Text(l.unblockAction)));
    final canSend = controller.text.trim().isNotEmpty;
    return Material(
      color: c.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x2, Space.x2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                maxLength: kMaxMessageLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(hintText: l.messageHint, counterText: ''),
              ),
            ),
            const SizedBox(width: Space.x1),
            IconButton.filled(tooltip: l.sendAction, onPressed: canSend ? onSend : null, icon: const Icon(Icons.arrow_upward_rounded)),
          ]),
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.showName, required this.onLongPress, this.onRetry});
  final Message message;
  final bool showName;
  final VoidCallback onLongPress;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final m = message;
    final tag = switch (m.role) { AuthorRole.senior => l.seniorTag, AuthorRole.coordinator => l.coordinatorTag, _ => null };
    final time = TimeOfDay.fromDateTime(m.sentAt).format(context);
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
        child: Padding(
          padding: const EdgeInsets.only(bottom: Space.x2),
          child: Column(crossAxisAlignment: m.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
            GestureDetector(
              onLongPress: onLongPress,
              onTap: onRetry,
              child: Semantics(
                label: m.mine ? null : m.authorName,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(Space.x3, Space.x2, Space.x3, Space.x2),
                  decoration: BoxDecoration(
                    color: m.mine ? c.lime : c.surface,
                    border: m.mine ? null : Border.all(color: c.outline),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(Radii.md),
                      topRight: const Radius.circular(Radii.md),
                      bottomLeft: Radius.circular(m.mine ? Radii.md : 4),
                      bottomRight: Radius.circular(m.mine ? 4 : Radii.md),
                    ),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (showName)
                      Text.rich(TextSpan(children: [
                        TextSpan(text: m.authorName, style: context.text.labelMedium?.copyWith(color: c.primaryStrong, fontWeight: FontWeight.w700)),
                        if (tag != null) TextSpan(text: ' · $tag', style: context.text.labelSmall?.copyWith(color: c.text2)),
                      ])),
                    Text(m.text, style: context.text.bodyLarge),
                    const SizedBox(height: 2),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(time, style: context.text.labelSmall?.copyWith(color: c.text2)),
                      if (m.mine) ...[
                        const SizedBox(width: 4),
                        Icon(
                          switch (m.status) { MessageStatus.sending => Icons.schedule_rounded, MessageStatus.sent => Icons.done_rounded, MessageStatus.failed => Icons.error_outline_rounded },
                          size: 14,
                          color: m.status == MessageStatus.failed ? c.danger : c.text2,
                        ),
                      ],
                    ]),
                  ]),
                ),
              ),
            ),
            if (m.status == MessageStatus.failed)
              Padding(padding: const EdgeInsets.only(top: 2), child: Text(l.failedRetry, style: context.text.labelSmall?.copyWith(color: c.danger))),
          ]),
        ),
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day), d = DateTime(date.year, date.month, date.day);
    final text = d == today ? l.todayLabel : (today.difference(d).inDays == 1 ? l.yesterdayLabel : chatTime(context, date));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.x2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: Space.x1),
        decoration: BoxDecoration(color: context.colors.surface2, borderRadius: BorderRadius.circular(Radii.pill)),
        child: Text(text, style: context.text.labelSmall?.copyWith(color: context.colors.text2)),
      ),
    );
  }
}

class _SystemLine extends StatelessWidget {
  const _SystemLine({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.x2, horizontal: Space.x6),
        child: Text(text, textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: context.colors.text2)),
      );
}

class _SafetyNote extends StatelessWidget {
  const _SafetyNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: Space.x3),
        padding: const EdgeInsets.all(Space.x3),
        decoration: BoxDecoration(color: context.colors.lime, borderRadius: BorderRadius.circular(Radii.sm)),
        child: Row(children: [
          Icon(Icons.shield_outlined, color: context.colors.primaryStrong, size: 20),
          const SizedBox(width: Space.x2),
          Expanded(child: Text(text, style: context.text.bodySmall)),
        ]),
      );
}
