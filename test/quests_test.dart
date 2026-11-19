import 'package:flutter_test/flutter_test.dart';
import 'package:taza_niyet/features/quests/data/quest_repository.dart';

void main() {
  // Среда, 18 ноября 2026, 09:00
  final now = DateTime(2026, 11, 18, 9);
  final all = FakeQuestRepository(now: now).all();
  const astana = (lat: 51.1282, lng: 71.4306);

  test('у каждой организации Астаны по 3 квеста', () {
    for (final org in ['tq', 'dl', 'kq', 'ze', 'eo', 'bv']) {
      expect(all.where((q) => q.orgId == org).length, 3);
    }
  });

  test('баллы: 1 ч = 5 Tz', () {
    final q = all.firstWhere((q) => q.title == 'Посадка деревьев в парке');
    expect(q.maxTz, 30); // 6 ч
  });

  test('без фильтров — все будущие, по времени начала', () {
    final rows = filterQuests(all, const QuestFilter(), now: now);
    expect(rows.length, all.length);
    for (var i = 1; i < rows.length; i++) {
      expect(rows[i].quest.startsAt.isBefore(rows[i - 1].quest.startsAt), isFalse);
    }
  });

  test('«Сегодня» и «Эта неделя» (до конца воскресенья)', () {
    final today = filterQuests(all, const QuestFilter(date: DateScope.today), now: now);
    expect(today, isNotEmpty);
    expect(today.every((r) => r.quest.startsAt.day == 18), isTrue);
    final week = filterQuests(all, const QuestFilter(date: DateScope.week), now: now);
    expect(week.every((r) => r.quest.startsAt.isBefore(DateTime(2026, 11, 23))), isTrue);
    expect(week.length, lessThan(all.length));
  });

  test('сложность — несколько сразу', () {
    final rows = filterQuests(all, const QuestFilter(difficulties: {Difficulty.easy, Difficulty.hard}), now: now);
    expect(rows.every((r) => r.quest.difficulty != Difficulty.medium), isTrue);
  });

  test('«До 3 км» работает только с геолокацией', () {
    expect(filterQuests(all, const QuestFilter(nearOnly: true), now: now), isEmpty);
    final near = filterQuests(all, const QuestFilter(nearOnly: true), me: astana, now: now);
    expect(near, isNotEmpty);
    expect(near.every((r) => r.km! <= 3), isTrue);
  });

  test('прошедшие квесты не показываются', () {
    final later = DateTime(2026, 11, 30);
    expect(filterQuests(all, const QuestFilter(), now: later), isEmpty);
  });

  test('заполненный квест — лист ожидания', () {
    final q = all.firstWhere((q) => q.title == 'Раздача продуктовых наборов');
    expect(q.isFull, isTrue);
    expect(q.spotsLeft, 0);
  });

  test('без организации видны все квесты города (только просмотр)', () async {
    final repo = FakeQuestRepository(now: now, delay: Duration.zero);
    expect((await repo.listPublic()).length, 18);
    expect((await repo.listForOrg('tq')).length, 3);
  });
}
