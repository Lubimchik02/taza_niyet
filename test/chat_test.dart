import 'package:flutter_test/flutter_test.dart';
import 'package:taza_niyet/features/chats/chats_controller.dart';
import 'package:taza_niyet/features/chats/data/chat_repository.dart';

void main() {
  final repo = FakeChatRepository(delay: Duration.zero, now: DateTime(2026, 11, 19, 12));
  const dm = Chat(id: 'dm-tk', kind: ChatKind.direct, title: 'Тимур К.', peerId: 'tk');
  const channel = Chat(id: 'org-tq', kind: ChatKind.channel, title: 'TazaQala');

  test('канал — только для чтения, личный — нет', () {
    expect(channel.readOnly, isTrue);
    expect(dm.readOnly, isFalse);
  });

  test('непрочитанные: чужие сообщения после отметки «прочитано»', () async {
    final h = await repo.history(dm);
    var st = ChatStoreState(messages: {dm.id: h});
    expect(unreadIn(st, dm.id), 2); // два сообщения от Тимура
    st = st.copyWith(read: {dm.id: DateTime(2026, 11, 19, 11)});
    expect(unreadIn(st, dm.id), 1); // осталось последнее (40 минут назад)
  });

  test('заблокированный: сообщения скрыты и не считаются', () async {
    final h = await repo.history(dm);
    final st = ChatStoreState(messages: {dm.id: h}, blocked: {'tk'});
    expect(unreadIn(st, dm.id), 0);
    expect(lastVisible(st, dm.id)!.mine, isTrue);
  });

  test('отправка: ошибка сети и повтор', () async {
    final draft = Message(id: 'x', chatId: dm.id, authorId: kMeId, authorName: '', text: 'тест !fail', sentAt: DateTime(2026), status: MessageStatus.sending);
    expect(() => repo.send(draft), throwsA(isA<ChatFailure>()));
    final ok = await repo.send(draft.withStatus(MessageStatus.failed));
    expect(ok.status, MessageStatus.sent);
  });
}
