import 'package:flutter_test/flutter_test.dart';
import 'package:taza_niyet/features/people/data/people_repository.dart';
import 'package:taza_niyet/features/profile/data/portfolio.dart';

void main() {
  const adult = Person(id: 'a', name: 'A', orgName: 'Жасыл Ел', city: 'astana', hours: 10, monthHours: 5, shifts: 3);
  const minor = Person(id: 'm', name: 'M', orgName: 'Жасыл Ел', city: 'astana', hours: 10, monthHours: 9, shifts: 3, minor: true);
  const hidden = Person(id: 'h', name: 'H', orgName: 'Жасыл Ел', city: 'astana', hours: 10, monthHours: 30, shifts: 3, visibility: HoursVisibility.onlyMe);

  test('видимость часов', () {
    expect(canSeeHours(adult, isFriend: false), isTrue);
    expect(canSeeHours(minor, isFriend: false), isFalse); // до 18 — только друзьям
    expect(canSeeHours(minor, isFriend: true), isTrue);
    expect(canSeeHours(hidden, isFriend: true), isFalse);
  });

  test('рейтинг: скрытые не попадают, я всегда есть, одинаковые часы — одно место', () {
    final rows = buildRating([adult, minor, hidden], scope: RatingScope.org, myOrg: 'Жасыл Ел', myCity: 'astana', myMonthHours: 5, myName: '', friends: const {});
    expect(rows.map((r) => r.id), isNot(contains('h')));
    expect(rows.map((r) => r.id), isNot(contains('m')));
    final me = rows.firstWhere((r) => r.isMe);
    expect(me.place, 1);
    expect(rows.firstWhere((r) => r.id == 'a').place, 1); // 5 ч = 5 ч
  });

  test('друг до 18 виден в рейтинге', () {
    final rows = buildRating([adult, minor], scope: RatingScope.org, myOrg: 'Жасыл Ел', myCity: 'astana', myMonthHours: 0, myName: '', friends: const {'m'});
    expect(rows.first.id, 'm');
  });

  test('поиск: с 2 букв, по началу имени или фамилии', () async {
    final repo = FakePeopleRepository(delay: Duration.zero);
    expect(await repo.search('т'), isEmpty);
    expect((await repo.search('тим')).single.id, 'tk');
    expect((await repo.search('ка')).map((p) => p.id), contains('kr'));
  });
}
