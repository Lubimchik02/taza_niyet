import '../../core/backend/backend.dart';
import '../../core/backend/supabase_data.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/connectivity.dart';
import '../offline/outbox.dart';
import '../org/data/org_repository.dart';
import '../people/people_controller.dart';
import '../org/org_controller.dart';
import '../quests/data/signup_repository.dart';
import '../quests/signups_controller.dart';
import 'data/chat_repository.dart';

// Сервер, если при сборке заданы SUPABASE_URL и SUPABASE_ANON_KEY; иначе демо.
final chatRepositoryProvider = Provider<ChatRepository>((ref) => Backend.enabled ? SupabaseChatRepository() : FakeChatRepository());


@immutable
class ChatStoreState {
  const ChatStoreState({this.messages = const {}, this.read = const {}, this.muted = const {}, this.blocked = const {}});

  final Map<String, List<Message>> messages; // chatId → по времени
  final Map<String, DateTime> read; // chatId → прочитано до
  final Set<String> muted;
  final Set<String> blocked; // userId

  ChatStoreState copyWith({Map<String, List<Message>>? messages, Map<String, DateTime>? read, Set<String>? muted, Set<String>? blocked}) =>
      ChatStoreState(messages: messages ?? this.messages, read: read ?? this.read, muted: muted ?? this.muted, blocked: blocked ?? this.blocked);
}

/// Сообщения, прочитанность, «без звука» и блокировки.
class ChatStore extends Notifier<ChatStoreState> {
  final _subs = <StreamSubscription<Message>>[];

  @override
  ChatStoreState build() {
    ref.onDispose(() {
      for (final s in _subs) {
        s.cancel();
      }
    });
    return const ChatStoreState();
  }

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  void _put(String chatId, List<Message> list) => state = state.copyWith(messages: {...state.messages, chatId: list});

  /// История чата (один раз). Ошибка пробрасывается — экран покажет «Повторить».
  Future<void> load(Chat chat) async {
    if (state.messages.containsKey(chat.id)) return;
    _put(chat.id, await _repo.history(chat));
    _subs.add(_repo.watch(chat).listen(_upsert)); // Realtime: сообщения других участников
  }

  Future<void> send(Chat chat, String text, {Message? retry}) async {
    final t = text.trim();
    if (t.isEmpty || t.length > kMaxMessageLength || chat.readOnly) return;
    final draft = retry?.withStatus(MessageStatus.sending) ??
        Message(id: 'm${DateTime.now().microsecondsSinceEpoch}', chatId: chat.id, authorId: kMeId, authorName: '', text: t, sentAt: DateTime.now(), status: MessageStatus.sending);
    _upsert(draft);
    if (!ref.read(isOnlineProvider)) {
      // Без сети: сообщение висит «отправляется» и уйдёт из очереди при появлении сети.
      await ref.read(outboxProvider.notifier).add(OutboxItem(id: 'msg-${draft.id}', type: 'message', ref: chat.id, at: draft.sentAt, payload: {'messageId': draft.id}));
      return;
    }
    try {
      final sent = await _repo.send(retry == null ? draft : draft.withStatus(MessageStatus.failed));
      _upsert(sent);
      markRead(chat.id);
      _subs.add(_repo.incoming(chat, sent).listen(_upsert));
    } catch (_) {
      _upsert(draft.withStatus(MessageStatus.failed));
    }
  }

  void _upsert(Message m) {
    final list = [...?state.messages[m.chatId]];
    final i = list.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      list[i] = m;
    } else {
      list.add(m);
    }
    _put(m.chatId, list);
  }

  void markRead(String chatId) => state = state.copyWith(read: {...state.read, chatId: DateTime.now()});

  void toggleMute(String chatId) =>
      state = state.copyWith(muted: state.muted.contains(chatId) ? ({...state.muted}..remove(chatId)) : {...state.muted, chatId});

  Future<void> setBlocked(String userId, bool blocked) async {
    await _repo.block(userId, blocked: blocked);
    state = state.copyWith(blocked: blocked ? {...state.blocked, userId} : ({...state.blocked}..remove(userId)));
  }

  Future<void> report({required String chatId, String? messageId, String? userId, required ReportReason reason}) =>
      _repo.report(chatId: chatId, messageId: messageId, userId: userId, reason: reason);
}

final chatStoreProvider = NotifierProvider<ChatStore, ChatStoreState>(ChatStore.new);

/// Список чатов: канал своей организации, чаты команд (по записям), личные с друзьями.
final chatsProvider = Provider<List<Chat>>((ref) {
  final m = ref.watch(membershipProvider);
  final signups = ref.watch(mySignupsProvider);
  return [
    if (m?.status == MembershipStatus.active) Chat(id: 'org-${m!.orgId}', kind: ChatKind.channel, title: m.orgName, members: 120),
    for (final s in signups.where((s) => s.status == SignupStatus.joined && s.team != null))
      Chat(id: 'team-${s.team!.id}', kind: ChatKind.team, title: s.quest.title, subtitle: s.team!.seniorName, questId: s.quest.id, members: s.team!.joined + 1),
    // Личные — только с друзьями (дружба взаимная).
    for (final f in ref.watch(friendPeopleProvider)) Chat(id: 'dm-${f.id}', kind: ChatKind.direct, title: f.name, peerId: f.id),
  ];
});

/// Последнее видимое сообщение (без заблокированных).
Message? lastVisible(ChatStoreState st, String chatId) =>
    st.messages[chatId]?.where((m) => m.role != AuthorRole.system && !st.blocked.contains(m.authorId)).lastOrNull;

int unreadIn(ChatStoreState st, String chatId) {
  final since = st.read[chatId];
  final list = st.messages[chatId];
  if (list == null) return 0;
  return list.where((m) => !m.mine && m.role != AuthorRole.system && !st.blocked.contains(m.authorId) && (since == null || m.sentAt.isAfter(since))).length;
}

/// Всего непрочитанных — для значка на вкладке (кроме чатов «без звука»).
final totalUnreadProvider = Provider<int>((ref) {
  final st = ref.watch(chatStoreProvider);
  return ref.watch(chatsProvider).where((c) => !st.muted.contains(c.id)).fold(0, (a, c) => a + unreadIn(st, c.id));
});

/// Подгрузить историю всех чатов (для превью и счётчика). В реальном приложении —
/// одна выборка «последнее сообщение + непрочитанные» и подписка Realtime.
final chatPreloadProvider = Provider<void>((ref) {
  final chats = ref.watch(chatsProvider);
  final store = ref.read(chatStoreProvider.notifier);
  for (final c in chats) {
    Future.microtask(() => store.load(c).catchError((_) {}));
  }
});
