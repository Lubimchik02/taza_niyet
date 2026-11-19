import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taza_niyet/core/geo.dart';
import 'package:taza_niyet/features/org/data/org_repository.dart';

void main() {
  const astana = (lat: 51.1282, lng: 71.4306);

  test('расстояние Астана — Алматы около 970 км', () {
    final km = distanceKm(astana, (lat: 43.2389, lng: 76.8897));
    expect(km, inInclusiveRange(940, 1000));
  });

  test('формат км: запятая для ru/kk, точка для en', () {
    expect(formatKm(0.84, 'ru'), '0,8');
    expect(formatKm(0.84, 'en'), '0.8');
    expect(formatKm(12.6, 'kk'), '13');
  });

  group('фильтр организаций', () {
    const orgs = FakeOrgRepository.orgs;

    test('«Рядом» — до 10 км, ближайшие первыми', () {
      final rows = filterOrgs(orgs, scope: OrgScope.nearby, cityId: 'astana', me: astana);
      expect(rows.first.org.name, 'TazaQala');
      expect(rows.every((r) => r.km! <= 10), isTrue);
      expect(rows.any((r) => r.org.name == 'Bars Volunteers'), isFalse); // ~14 км
    });

    test('«Мой город» без геолокации', () {
      final rows = filterOrgs(orgs, scope: OrgScope.city, cityId: 'almaty');
      expect(rows.map((r) => r.org.name), ['Taza Almaty']);
    });

    test('поиск по названию без учёта регистра', () {
      final rows = filterOrgs(orgs, scope: OrgScope.all, cityId: 'astana', query: 'жасыл');
      expect(rows.single.org.id, 'ze');
    });
  });

  group('заявка', () {
    late FakeOrgRepository repo;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repo = FakeOrgRepository(await SharedPreferences.getInstance(), delay: Duration.zero, decision: Duration.zero);
    });

    test('код приглашения — с пробелами и в нижнем регистре', () async {
      expect((await repo.findByInviteCode(' taza 2026 ')).id, 'tq');
      expect(() => repo.findByInviteCode('NOPE'), throwsA(isA<OrgFailure>()));
    });

    test('заявка → на рассмотрении → одобрена и сохранена', () async {
      final org = FakeOrgRepository.orgs.first;
      final m = await repo.requestJoin(org);
      expect(m.status, MembershipStatus.pending);
      final d = await repo.awaitDecision(m);
      expect(d.status, MembershipStatus.active);
      expect(repo.saved?.status, MembershipStatus.active);
    });

    test('отказ и отмена', () async {
      final bars = FakeOrgRepository.orgs.firstWhere((o) => o.id == 'bv');
      final d = await repo.awaitDecision(await repo.requestJoin(bars));
      expect(d.status, MembershipStatus.rejected);
      await repo.cancel(d);
      expect(repo.saved, isNull);
    });
  });
}
