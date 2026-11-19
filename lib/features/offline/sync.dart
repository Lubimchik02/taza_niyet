import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../chats/chats_controller.dart';
import '../chats/data/chat_repository.dart';
import '../quests/signups_controller.dart';
import '../shift/shift_controller.dart';
import 'outbox.dart';

/// Отправить всё из очереди. Возвращает число отправленных действий.
/// Реальный сервер: отметки уходят с исходным временем и геометкой — часы считаются по ним.
Future<int> flushOutbox(WidgetRef ref) async {
  final items = [...ref.read(outboxProvider)];
  final box = ref.read(outboxProvider.notifier);
  var sent = 0;
  for (final i in items) {
    try {
      switch (i.type) {
        case 'checkin':
          final s = ref.read(mySignupsProvider.notifier).forQuest(i.ref);
          final lat = i.payload['lat'] as double?, lng = i.payload['lng'] as double?;
          if (s != null) await ref.read(shiftRepositoryProvider).checkIn(s.quest, at: lat == null || lng == null ? null : (lat: lat, lng: lng), time: i.at);
        case 'message':
          final chat = ref.read(chatsProvider).where((c) => c.id == i.ref).firstOrNull;
          final m = ref.read(chatStoreProvider).messages[i.ref]?.where((x) => x.id == i.payload['messageId']).firstOrNull;
          if (chat != null && m != null) await ref.read(chatStoreProvider.notifier).send(chat, m.text, retry: m.withStatus(MessageStatus.failed));
      }
      await box.remove(i.id);
      sent++;
    } catch (_) {
      // Оставляем в очереди — попробуем при следующем появлении сети.
    }
  }
  return sent;
}
