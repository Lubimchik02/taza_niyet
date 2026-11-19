import 'package:flutter_test/flutter_test.dart';
import 'package:taza_niyet/core/config/app_config.dart';
import 'package:taza_niyet/features/notifications/notifications.dart';
import 'package:taza_niyet/features/offline/outbox.dart';
import 'package:taza_niyet/features/quests/data/quest_repository.dart';

void main() {
  test('сравнение версий', () {
    expect(compareVersions('2.0.0', '2.0.0'), 0);
    expect(compareVersions('2.0.9', '2.1.0'), -1);
    expect(compareVersions('2.10.0', '2.9.3'), 1);
    expect(compareVersions('2.1', '2.1.0+15'), 0);
  });

  test('статус обновления', () {
    const c = AppConfig(minVersion: '2.1.0', latestVersion: '2.3.0');
    expect(updateStatus('2.0.5', c), UpdateStatus.required);
    expect(updateStatus('2.2.0', c), UpdateStatus.available);
    expect(updateStatus('2.3.0', c), UpdateStatus.upToDate);
  });

  test('неизвестный флаг — включён, выключенный — выключен', () {
    const c = AppConfig(flags: {Flags.rating: false});
    expect(c.flag(Flags.rating), isFalse);
    expect(c.flag(Flags.chats), isTrue);
  });

  test('напоминания: за день и за час, прошедшие пропускаются', () {
    final now = DateTime(2026, 11, 19, 9);
    final q = FakeQuestRepository(now: now).all().firstWhere((q) => q.title == 'Полив саженцев'); // через 2 ч
    final times = reminderTimes(q, now);
    expect(times, hasLength(1)); // «за день» уже прошло
    expect(times.single, q.startsAt.subtract(const Duration(hours: 1)));
  });

  test('очередь без сети: сериализация', () {
    final i = OutboxItem(id: 'ci-q1', type: 'checkin', ref: 'q1', at: DateTime(2026, 11, 19, 10, 5), payload: {'geo': true});
    final back = OutboxItem.fromJson(i.toJson());
    expect(back.ref, 'q1');
    expect(back.payload['geo'], isTrue);
    expect(back.at, i.at);
  });
}
