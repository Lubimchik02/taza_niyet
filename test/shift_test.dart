import 'package:flutter_test/flutter_test.dart';
import 'package:taza_niyet/features/quests/data/quest_repository.dart';
import 'package:taza_niyet/features/quests/data/signup_repository.dart';
import 'package:taza_niyet/features/shift/data/shift_repository.dart';

void main() {
  final now = DateTime(2026, 11, 18, 9);
  final q = FakeQuestRepository(now: now).all().firstWhere((q) => q.title == 'Посадка деревьев в парке'); // 6 ч

  test('окно отметки: за 30 минут до начала и до конца', () {
    expect(checkInWindow(q, q.startsAt.subtract(const Duration(minutes: 31))), CheckInWindow.notYet);
    expect(checkInWindow(q, q.startsAt.subtract(const Duration(minutes: 30))), CheckInWindow.open);
    expect(checkInWindow(q, q.endsAt), CheckInWindow.open);
    expect(checkInWindow(q, q.endsAt.add(const Duration(minutes: 1))), CheckInWindow.ended);
  });

  test('геометка: до 300 м — подтверждена, дальше — «слишком далеко»', () {
    final near = (lat: q.location.lat + 0.001, lng: q.location.lng); // ~111 м
    final far = (lat: q.location.lat + 0.01, lng: q.location.lng); // ~1,1 км
    expect(evaluateCheckIn(quest: q, me: near, now: now), isA<CheckedIn>().having((r) => r.geoVerified, 'geo', true));
    expect(evaluateCheckIn(quest: q, me: far, now: now), isA<TooFar>());
    expect(evaluateCheckIn(quest: q, me: far, now: now, force: true), isA<CheckedIn>().having((r) => r.geoVerified, 'geo', false));
    expect(evaluateCheckIn(quest: q, me: null, now: now), isA<NeedsLocation>());
  });

  test('квест «отметка из любого места» не проверяет расстояние', () {
    final anywhere = Quest(
      id: q.id, orgId: q.orgId, orgName: q.orgName, title: q.title, description: q.description, difficulty: q.difficulty,
      startsAt: q.startsAt, duration: q.duration, location: q.location, address: q.address, capacity: q.capacity,
      joined: q.joined, seniorName: q.seniorName, checkInAnywhere: true,
    );
    expect(evaluateCheckIn(quest: anywhere, me: null, now: now), isA<CheckedIn>().having((r) => r.geoVerified, 'geo', true));
    expect(evaluateCheckIn(quest: anywhere, me: (lat: 0.0, lng: 0.0), now: now), isA<CheckedIn>());
  });

  test('часы нельзя завысить, шаг 0,5', () {
    expect(clampHours(9, q), 6);
    expect(clampHours(-1, q), 0);
    expect(clampHours(2.3, q), 2.5);
    expect(tzForHours(2.5), 13); // 12,5 → 13
    expect(tzForHours(6), 30);
  });

  test('отчёт старшего: итоги и ручные отметки', () {
    final r = ShiftReport(questId: q.id, teamId: 't', members: [
      RosterMember(id: 'a', name: 'A', checkedInAt: now, geoVerified: true, hours: 6),
      const RosterMember(id: 'b', name: 'B', markedBySenior: true, hours: 4),
      const RosterMember(id: 'c', name: 'C', hours: 6),
    ]);
    expect(r.presentCount, 2);
    expect(r.absentCount, 1);
    expect(r.totalHours, 10);
    expect(r.manualCount, 1);
  });

  test('список команды: я + остальные участники', () async {
    final team = splitIntoTeams(q).first;
    final me = Signup(quest: q, status: SignupStatus.joined, team: team);
    final list = await FakeShiftRepository(delay: Duration.zero).roster(q, team, myName: 'Айгерим', mine: me);
    expect(list.length, team.joined);
    expect(list.first.isMe, isTrue);
    expect(list.where((m) => !m.present), isNotEmpty);
  });
}
