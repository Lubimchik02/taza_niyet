import 'package:flutter/foundation.dart';

import '../../profile/data/portfolio.dart';

/// Волонтёр, каким его видят другие. Часы приходят с сервера уже с учётом настроек
/// видимости (RLS); здесь те же правила повторены для демо и тестов.
@immutable
class Person {
  const Person({
    required this.id,
    required this.name,
    required this.orgName,
    required this.city,
    required this.hours,
    required this.monthHours,
    required this.shifts,
    this.minor = false,
    this.visibility = HoursVisibility.everyone,
    this.achievements = const [],
  });

  final String id, name, orgName, city;
  final double hours, monthHours;
  final int shifts;
  final bool minor;
  final HoursVisibility visibility;
  final List<AchievementId> achievements;

  int get tz => (hours * 5).round();
}

/// Видны ли часы человека мне. До 18 лет — только друзьям, «только я» — никому.
bool canSeeHours(Person p, {required bool isFriend}) => switch (effectiveVisibility(p.visibility, minor: p.minor)) {
      HoursVisibility.everyone => true,
      HoursVisibility.friends => isFriend,
      HoursVisibility.onlyMe => false,
    };

enum RatingScope { org, city }

@immutable
class RatingRow {
  const RatingRow({required this.place, required this.id, required this.name, required this.monthHours, this.isMe = false});
  final int place;
  final String id, name;
  final double monthHours;
  final bool isMe;
}

/// Рейтинг месяца: только те, чьи часы мне видны; я — всегда. Одинаковые часы — одно место.
List<RatingRow> buildRating(List<Person> people, {required RatingScope scope, required String myOrg, required String myCity, required double myMonthHours, required String myName, required Set<String> friends}) {
  final rows = [
    for (final p in people)
      if ((scope == RatingScope.org ? p.orgName == myOrg : p.city == myCity) && canSeeHours(p, isFriend: friends.contains(p.id)) && p.monthHours > 0)
        (id: p.id, name: p.name, h: p.monthHours, me: false),
    (id: 'me', name: myName, h: myMonthHours, me: true),
  ]..sort((a, b) => b.h.compareTo(a.h));
  final out = <RatingRow>[];
  for (var i = 0; i < rows.length; i++) {
    final place = i > 0 && rows[i].h == rows[i - 1].h ? out[i - 1].place : i + 1;
    out.add(RatingRow(place: place, id: rows[i].id, name: rows[i].name, monthHours: rows[i].h, isMe: rows[i].me));
  }
  return out;
}

/// Контракт. Реальный — Supabase: поиск по имени (pg_trgm), таблица friendships со статусом,
/// рейтинг — представление по подтверждённым начислениям за месяц (этап 12).
abstract interface class PeopleRepository {
  Future<List<Person>> search(String query);
  Future<Person?> byId(String id);
  Future<List<Person>> all();
  Future<void> sendRequest(String id);
  Future<bool> awaitAnswer(String id);

  /// Друзья и заявки с сервера; null — демо (оставить локальные).
  Future<({Set<String> friends, Set<String> outgoing, Set<String> incoming})?> loadFriends();
  Future<void> respond(String id, {required bool accept});
  Future<void> remove(String id);

  /// Уже загруженный человек (имя для списков друзей и чатов) — без запроса.
  Person? cached(String id);
}

class FakePeopleRepository implements PeopleRepository {
  FakePeopleRepository({this.delay = const Duration(milliseconds: 350)});
  final Duration delay;

  static const _a = AchievementId.values;
  static final people = <Person>[
    Person(id: 'tk', name: 'Тимур К.', orgName: 'Жасыл Ел', city: 'astana', hours: 42, monthHours: 14, shifts: 11, achievements: [_a[0], _a[1], _a[2], _a[3]]),
    Person(id: 'ds', name: 'Дана С.', orgName: 'TazaQala', city: 'astana', hours: 27.5, monthHours: 9, shifts: 8, achievements: [_a[0], _a[1], _a[2], _a[3]]),
    Person(id: 'am', name: 'Аружан М.', orgName: 'Жасыл Ел', city: 'astana', hours: 18, monthHours: 6, shifts: 5, minor: true, visibility: HoursVisibility.friends, achievements: [_a[0], _a[1], _a[2]]),
    Person(id: 'ab', name: 'Алия Б.', orgName: 'Жасыл Ел', city: 'astana', hours: 63, monthHours: 21, shifts: 17, achievements: [_a[0], _a[1], _a[2], _a[3], _a[4], _a[5]]),
    Person(id: 'ea', name: 'Ержан А.', orgName: 'Жасыл Ел', city: 'astana', hours: 31, monthHours: 12, shifts: 9),
    Person(id: 'kr', name: 'Камила Р.', orgName: 'Добрые лапы', city: 'astana', hours: 55, monthHours: 18, shifts: 20),
    Person(id: 'nj', name: 'Нурсултан Ж.', orgName: 'TazaQala', city: 'astana', hours: 12, monthHours: 4, shifts: 4),
    Person(id: 'se', name: 'Санжар Е.', orgName: 'Жасыл Ел', city: 'astana', hours: 8, monthHours: 8, shifts: 3, visibility: HoursVisibility.onlyMe),
    Person(id: 'mo', name: 'Мира О.', orgName: 'Қамқор', city: 'astana', hours: 36, monthHours: 10, shifts: 12),
    Person(id: 'at', name: 'Арман Т.', orgName: 'Жасыл Ел', city: 'astana', hours: 88, monthHours: 16, shifts: 25, achievements: _a),
    Person(id: 'dk', name: 'Данияр С.', orgName: 'TazaQala', city: 'astana', hours: 71, monthHours: 15, shifts: 22, achievements: _a),
    Person(id: 'gb', name: 'Гаухар Б.', orgName: 'Taza Almaty', city: 'almaty', hours: 40, monthHours: 11, shifts: 13),
  ];

  @override
  Future<List<Person>> search(String query) async {
    await Future<void>.delayed(delay);
    final q = query.trim().toLowerCase();
    if (q.length < 2) return const [];
    return people.where((p) => p.name.toLowerCase().split(RegExp(r'[\s.]+')).any((w) => w.startsWith(q)) || p.name.toLowerCase().startsWith(q)).toList();
  }

  @override
  Future<Person?> byId(String id) async {
    await Future<void>.delayed(delay);
    return people.where((p) => p.id == id).firstOrNull;
  }

  @override
  Future<List<Person>> all() async {
    await Future<void>.delayed(delay);
    return people;
  }

  @override
  Future<void> sendRequest(String id) => Future<void>.delayed(delay);

  @override
  Future<({Set<String> friends, Set<String> outgoing, Set<String> incoming})?> loadFriends() async => null;

  @override
  Future<void> respond(String id, {required bool accept}) async {}

  @override
  Future<void> remove(String id) async {}

  @override
  Person? cached(String id) => people.where((p) => p.id == id).firstOrNull;

  /// Демо: через 3 с соглашаются все, кроме Санжара (он скрыт и заявки не принимает).
  @override
  Future<bool> awaitAnswer(String id) async {
    await Future<void>.delayed(const Duration(seconds: 3));
    return id != 'se';
  }
}
