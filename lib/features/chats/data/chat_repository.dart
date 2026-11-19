import 'package:flutter/foundation.dart';

enum ChatKind { team, direct, channel }

/// Чат в списке. Команда — создаётся для каждой команды квеста; канал — один на организацию
/// (пишет только координатор); личные — только между друзьями.
@immutable
class Chat {
  const Chat({required this.id, required this.kind, required this.title, this.subtitle, this.questId, this.peerId, this.members = 2});

  final String id;
  final ChatKind kind;
  final String title;
  final String? subtitle;
  final String? questId;
  final String? peerId;
  final int members;

  bool get readOnly => kind == ChatKind.channel;
}

enum MessageStatus { sending, sent, failed }

enum AuthorRole { member, senior, coordinator, system }

@immutable
class Message {
  const Message({required this.id, required this.chatId, required this.authorId, required this.authorName, required this.text, required this.sentAt, this.status = MessageStatus.sent, this.role = AuthorRole.member});

  final String id, chatId, authorId, authorName, text;
  final DateTime sentAt;
  final MessageStatus status;
  final AuthorRole role;

  bool get mine => authorId == kMeId;

  Message withStatus(MessageStatus s) => Message(id: id, chatId: chatId, authorId: authorId, authorName: authorName, text: text, sentAt: sentAt, status: s, role: role);
}

const kMeId = 'me';
const kMaxMessageLength = 2000;

enum ReportReason { spam, insult, inappropriate, danger, other }

class ChatFailure implements Exception {
  const ChatFailure();
}

/// Контракт. Реальный — Supabase Realtime (каналы на чат), RLS: читать/писать может только участник,
/// в канал пишет только координатор, личные — только между друзьями; жалобы — в очередь модерации (этап 12).
abstract interface class ChatRepository {
  Future<List<Message>> history(Chat chat);
  Future<Message> send(Message draft);

  /// Ответ собеседника — в демо имитируем, в реальном — поток Realtime.
  Stream<Message> incoming(Chat chat, Message sent);

  /// Новые сообщения чата в реальном времени (Supabase Realtime). В демо — пусто.
  Stream<Message> watch(Chat chat);
  Future<void> report({required String chatId, String? messageId, String? userId, required ReportReason reason});
  Future<void> block(String userId, {required bool blocked});
}

class FakeChatRepository implements ChatRepository {
  FakeChatRepository({this.delay = const Duration(milliseconds: 400), DateTime? now}) : _now = now;
  final Duration delay;
  final DateTime? _now;

  DateTime get now => _now ?? DateTime.now();

  @override
  Future<List<Message>> history(Chat chat) async {
    await Future<void>.delayed(delay);
    final n = now;
    Message m(String id, String author, String name, String text, Duration ago, [AuthorRole role = AuthorRole.member]) =>
        Message(id: '${chat.id}-$id', chatId: chat.id, authorId: author, authorName: name, text: text, sentAt: n.subtract(ago), role: role);
    return switch (chat.kind) {
      ChatKind.channel => [
          m('1', 'coord', 'Айжан Б.', 'Друзья, в субботу большой субботник в центральном парке. Записывайтесь на карте!', const Duration(days: 1, hours: 3), AuthorRole.coordinator),
          m('2', 'coord', 'Айжан Б.', 'Спасибо всем, кто вышел на уборку набережной: 46 мешков мусора!', const Duration(hours: 5), AuthorRole.coordinator),
        ],
      // Демо: переписка есть только с первыми друзьями; с новыми чат пустой.
      ChatKind.direct when !const {'tk', 'ds'}.contains(chat.peerId) => const [],
      ChatKind.direct => [
          m('1', chat.peerId!, chat.title, 'Привет! Пойдёшь в субботу на посадку деревьев?', const Duration(hours: 20)),
          m('2', kMeId, '', 'Думаю да, если не будет дождя', const Duration(hours: 19)),
          m('3', chat.peerId!, chat.title, 'Супер, возьми перчатки 🙂', const Duration(minutes: 40)),
        ],
      ChatKind.team => [
          m('0', 'system', '', '', const Duration(minutes: 30), AuthorRole.system),
          m('1', 'senior', chat.subtitle ?? '', 'Всем привет! Встречаемся у главного входа за 10 минут до начала. Возьмите воду', const Duration(minutes: 25), AuthorRole.senior),
          m('2', 'u2', 'Тимур К.', 'Принято!', const Duration(minutes: 20)),
        ],
    };
  }

  @override
  Future<Message> send(Message draft) async {
    await Future<void>.delayed(delay);
    if (draft.text.contains('!fail') && draft.status != MessageStatus.failed) throw const ChatFailure(); // демо ошибки
    return draft.withStatus(MessageStatus.sent);
  }

  @override
  Stream<Message> incoming(Chat chat, Message sent) async* {
    if (chat.kind == ChatKind.channel) return;
    await Future<void>.delayed(const Duration(seconds: 2));
    final (id, name, role, text) = chat.kind == ChatKind.team
        ? ('senior', chat.subtitle ?? '', AuthorRole.senior, 'Принято, ждём вас!')
        : (chat.peerId!, chat.title, AuthorRole.member, 'Ок, договорились 👍');
    yield Message(id: 'r${sent.id}', chatId: chat.id, authorId: id, authorName: name, text: text, sentAt: DateTime.now(), role: role);
  }

  @override
  Stream<Message> watch(Chat chat) => const Stream.empty();

  @override
  Future<void> report({required String chatId, String? messageId, String? userId, required ReportReason reason}) => Future<void>.delayed(delay);

  @override
  Future<void> block(String userId, {required bool blocked}) => Future<void>.delayed(delay);
}
