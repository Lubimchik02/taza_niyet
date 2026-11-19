import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/geo.dart';

enum OrgType { ecology, animals, social, greening, youth, sports }

@immutable
class City {
  const City(this.id, this.ru, this.kk, this.en, this.center);
  final String id, ru, kk, en;
  final LatLng center;

  String name(String lang) => switch (lang) { 'kk' => kk, 'en' => en, _ => ru };
}

const kCities = [
  City('astana', 'Астана', 'Астана', 'Astana', (lat: 51.1282, lng: 71.4306)),
  City('almaty', 'Алматы', 'Алматы', 'Almaty', (lat: 43.2389, lng: 76.8897)),
  City('shymkent', 'Шымкент', 'Шымкент', 'Shymkent', (lat: 42.3417, lng: 69.5901)),
  City('karaganda', 'Караганда', 'Қарағанды', 'Karaganda', (lat: 49.8060, lng: 73.0850)),
  City('aktobe', 'Актобе', 'Ақтөбе', 'Aktobe', (lat: 50.2839, lng: 57.1670)),
  City('atyrau', 'Атырау', 'Атырау', 'Atyrau', (lat: 47.1167, lng: 51.8830)),
  City('oral', 'Уральск', 'Орал', 'Oral', (lat: 51.2333, lng: 51.3667)),
];

/// Название организации не переводится.
@immutable
class Organization {
  const Organization({required this.id, required this.name, required this.type, required this.cityId, required this.location, required this.members, this.verified = true});
  final String id, name, cityId;
  final OrgType type;
  final LatLng location;
  final int members;
  final bool verified;
}

enum MembershipStatus { pending, active, rejected }

@immutable
class Membership {
  const Membership({required this.orgId, required this.orgName, required this.status});
  final String orgId, orgName;
  final MembershipStatus status;

  Map<String, Object?> toJson() => {'orgId': orgId, 'orgName': orgName, 'status': status.name};
  static Membership fromJson(Map<String, Object?> j) => Membership(
        orgId: j['orgId']! as String,
        orgName: j['orgName']! as String,
        status: MembershipStatus.values.byName(j['status']! as String),
      );
}

class OrgFailure implements Exception {
  const OrgFailure(this.reason);
  final String reason; // network | code_not_found
}

/// Контракт. Реальный — Supabase (таблицы organizations, org_members), этап 12.
abstract interface class OrgRepository {
  Future<List<Organization>> list();
  Future<Organization> findByInviteCode(String code);
  Future<Membership> requestJoin(Organization org);
  /// Ответ координатора. В реальности — push и Realtime; в демо — через 4 секунды.
  Future<Membership> awaitDecision(Membership pending);
  Future<void> cancel(Membership m);
  Membership? get saved;
  Future<void> save(Membership? m);
}

/// Демо. Код TAZA2026 → TazaQala, ZHASYL → Жасыл Ел; Bars Volunteers отклоняет заявку.
class FakeOrgRepository implements OrgRepository {
  FakeOrgRepository(this._prefs, {this.delay = const Duration(milliseconds: 600), this.decision = const Duration(seconds: 4)});

  final SharedPreferences _prefs;
  final Duration delay, decision;
  static const _k = 'demo.org.membership';

  static const orgs = [
    Organization(id: 'tq', name: 'TazaQala', type: OrgType.ecology, cityId: 'astana', location: (lat: 51.135, lng: 71.43), members: 148),
    Organization(id: 'dl', name: 'Добрые лапы', type: OrgType.animals, cityId: 'astana', location: (lat: 51.149, lng: 71.40), members: 62),
    Organization(id: 'kq', name: 'Қамқор', type: OrgType.social, cityId: 'astana', location: (lat: 51.10, lng: 71.42), members: 95),
    Organization(id: 'ze', name: 'Жасыл Ел', type: OrgType.greening, cityId: 'astana', location: (lat: 51.09, lng: 71.39), members: 210),
    Organization(id: 'eo', name: 'El Omit', type: OrgType.youth, cityId: 'astana', location: (lat: 51.16, lng: 71.47), members: 340),
    Organization(id: 'bv', name: 'Bars Volunteers', type: OrgType.sports, cityId: 'astana', location: (lat: 51.23, lng: 71.55), members: 77),
    Organization(id: 'ta', name: 'Taza Almaty', type: OrgType.ecology, cityId: 'almaty', location: (lat: 43.24, lng: 76.90), members: 120),
    Organization(id: 'gk', name: 'Green Qaraganda', type: OrgType.ecology, cityId: 'karaganda', location: (lat: 49.80, lng: 73.10), members: 54),
  ];

  static const _codes = {'TAZA2026': 'tq', 'ZHASYL': 'ze'};

  @override
  Future<List<Organization>> list() async {
    await Future<void>.delayed(delay);
    return orgs;
  }

  @override
  Future<Organization> findByInviteCode(String code) async {
    await Future<void>.delayed(delay);
    final id = _codes[code.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '')];
    if (id == null) throw const OrgFailure('code_not_found');
    return orgs.firstWhere((o) => o.id == id);
  }

  @override
  Future<Membership> requestJoin(Organization org) async {
    await Future<void>.delayed(delay);
    final m = Membership(orgId: org.id, orgName: org.name, status: MembershipStatus.pending);
    await save(m);
    return m;
  }

  @override
  Future<Membership> awaitDecision(Membership pending) async {
    await Future<void>.delayed(decision);
    final m = Membership(
      orgId: pending.orgId,
      orgName: pending.orgName,
      status: pending.orgId == 'bv' ? MembershipStatus.rejected : MembershipStatus.active,
    );
    await save(m);
    return m;
  }

  @override
  Future<void> cancel(Membership m) => save(null);

  @override
  Membership? get saved {
    final raw = _prefs.getString(_k);
    return raw == null ? null : Membership.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  @override
  Future<void> save(Membership? m) async {
    if (m == null) {
      await _prefs.remove(_k);
    } else {
      await _prefs.setString(_k, jsonEncode(m.toJson()));
    }
  }
}

/// Сортировка и фильтр списка — чистая функция, легко тестировать.
enum OrgScope { nearby, city, all }

List<({Organization org, double? km})> filterOrgs(
  List<Organization> orgs, {
  required OrgScope scope,
  required String cityId,
  LatLng? me,
  String query = '',
  double nearbyKm = 10,
}) {
  final q = query.trim().toLowerCase();
  final rows = [
    for (final o in orgs)
      (org: o, km: me == null ? null : distanceKm(me, o.location)),
  ].where((r) {
    if (q.isNotEmpty && !r.org.name.toLowerCase().contains(q)) return false;
    return switch (scope) {
      OrgScope.nearby => r.km != null && r.km! <= nearbyKm,
      OrgScope.city => r.org.cityId == cityId,
      OrgScope.all => true,
    };
  }).toList()
    ..sort((a, b) => (a.km ?? 1e9).compareTo(b.km ?? 1e9));
  return rows;
}
