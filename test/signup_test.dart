import 'package:flutter_test/flutter_test.dart';
import 'package:taza_niyet/features/quests/data/quest_repository.dart';
import 'package:taza_niyet/features/quests/data/signup_repository.dart';

void main() {
  final now = DateTime(2026, 11, 18, 9);
  final all = FakeQuestRepository(now: now).all();
  Quest byTitle(String t) => all.firstWhere((q) => q.title == t);

  test('места делятся на команды по 10, сумма сходится', () {
    final q = byTitle('Посадка деревьев в парке'); // 30 мест, 9 занято
    final teams = splitIntoTeams(q);
    expect(teams.length, 3);
    expect(teams.fold<int>(0, (a, t) => a + t.capacity), 30);
    expect(teams.fold<int>(0, (a, t) => a + t.joined), 9);
    expect(teams.first.seniorName, q.seniorName);
  });

  test('запись в свободную команду, повторно — нельзя', () async {
    final repo = FakeSignupRepository(delay: Duration.zero);
    final q = byTitle('Полив саженцев');
    final s = await repo.join(q, mine: const []);
    expect(s.status, SignupStatus.joined);
    expect(s.team, isNotNull);
    expect(() => repo.join(q, mine: [s]), throwsA(isA<SignupFailure>().having((e) => e.kind, 'kind', SignupFailureKind.alreadySigned)));
  });

  test('мест нет — лист ожидания с номером', () async {
    final repo = FakeSignupRepository(delay: Duration.zero);
    final q = byTitle('Раздача продуктовых наборов'); // 15 из 15
    final s = await repo.join(q, mine: const []);
    expect(s.status, SignupStatus.waitlist);
    expect(s.position, 3); // в демо уже ждут двое
  });

  test('пересечение по времени запрещено', () async {
    final repo = FakeSignupRepository(delay: Duration.zero);
    final a = byTitle('Полив саженцев');
    final clash = Quest(
      id: 'x', orgId: a.orgId, orgName: a.orgName, title: 'X', description: '', difficulty: Difficulty.easy,
      startsAt: a.startsAt.add(const Duration(hours: 1)), duration: const Duration(hours: 2),
      location: a.location, address: '', capacity: 10, joined: 0, seniorName: 'S',
    );
    final s = await repo.join(a, mine: const []);
    expect(() => repo.join(clash, mine: [s]), throwsA(isA<SignupFailure>().having((e) => e.kind, 'kind', SignupFailureKind.timeConflict)));
  });

  test('отмена освобождает место в команде', () async {
    final repo = FakeSignupRepository(delay: Duration.zero);
    final q = byTitle('Полив саженцев');
    final before = (await repo.teams(q)).first.joined;
    final s = await repo.join(q, mine: const []);
    expect((await repo.teams(q)).first.joined, before + 1);
    await repo.leave(s);
    expect((await repo.teams(q)).first.joined, before);
  });
}
