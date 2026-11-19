import 'package:flutter/foundation.dart';

import '../../../core/geo.dart';

enum Difficulty { easy, medium, hard }

/// Квест. Название и описание пишет координатор — они не переводятся.
@immutable
class Quest {
  const Quest({
    required this.id,
    required this.orgId,
    required this.orgName,
    required this.title,
    required this.description,
    required this.difficulty,
    required this.startsAt,
    required this.duration,
    required this.location,
    required this.address,
    required this.capacity,
    required this.joined,
    required this.seniorName,
    this.checkInAnywhere = false,
  });

  final String id, orgId, orgName, title, description, address, seniorName;

  /// Отметка без проверки расстояния: онлайн-акции и тестовые квесты для проверки в магазинах.
  final bool checkInAnywhere;
  final Difficulty difficulty;
  final DateTime startsAt;
  final Duration duration;
  final LatLng location;
  final int capacity, joined;

  int get spotsLeft => (capacity - joined).clamp(0, capacity);
  bool get isFull => spotsLeft == 0;
  DateTime get endsAt => startsAt.add(duration);

  /// Для демо: перенести начало (смена «сейчас»).
  Quest copyWith({DateTime? startsAt}) => Quest(
        id: id, orgId: orgId, orgName: orgName, title: title, description: description, difficulty: difficulty,
        startsAt: startsAt ?? this.startsAt, duration: duration, location: location, address: address,
        capacity: capacity, joined: joined, seniorName: seniorName, checkInAnywhere: checkInAnywhere,
      );

  /// Максимум баллов за квест: 1 ч = 5 Tz.
  int get maxTz => (duration.inMinutes / 60 * 5).round();
}

enum DateScope { any, today, week }

@immutable
class QuestFilter {
  const QuestFilter({this.date = DateScope.any, this.difficulties = const {}, this.nearOnly = false});

  final DateScope date;
  final Set<Difficulty> difficulties;
  final bool nearOnly; // до 3 км

  bool get isEmpty => date == DateScope.any && difficulties.isEmpty && !nearOnly;

  QuestFilter copyWith({DateScope? date, Set<Difficulty>? difficulties, bool? nearOnly}) => QuestFilter(
        date: date ?? this.date,
        difficulties: difficulties ?? this.difficulties,
        nearOnly: nearOnly ?? this.nearOnly,
      );
}

/// Фильтр и сортировка (по времени начала) — чистая функция.
List<({Quest quest, double? km})> filterQuests(List<Quest> all, QuestFilter f, {LatLng? me, required DateTime now}) {
  final startOfToday = DateTime(now.year, now.month, now.day);
  final endOfToday = startOfToday.add(const Duration(days: 1));
  final endOfWeek = startOfToday.add(Duration(days: 8 - now.weekday)); // до конца воскресенья
  return [
    for (final q in all) (quest: q, km: me == null ? null : distanceKm(me, q.location)),
  ].where((r) {
    final q = r.quest;
    if (q.startsAt.add(q.duration).isBefore(now)) return false; // уже прошёл
    if (f.date == DateScope.today && !q.startsAt.isBefore(endOfToday)) return false;
    if (f.date == DateScope.week && !q.startsAt.isBefore(endOfWeek)) return false;
    if (f.difficulties.isNotEmpty && !f.difficulties.contains(q.difficulty)) return false;
    if (f.nearOnly && (r.km == null || r.km! > 3)) return false;
    return true;
  }).toList()
    ..sort((a, b) => a.quest.startsAt.compareTo(b.quest.startsAt));
}

/// Контракт. Реальный — Supabase: опубликованные квесты своей организации (RLS), этап 12.
abstract interface class QuestRepository {
  Future<List<Quest>> listForOrg(String orgId);

  /// Все открытые квесты города — для тех, кто ещё не вступил в организацию (только просмотр).
  Future<List<Quest>> listPublic();

  /// Один квест по id — для ссылок-приглашений (квест может быть не в загруженном списке).
  Future<Quest?> byId(String id);
}

/// Демо: по 3 квеста у каждой организации Астаны, на ближайшие 10 дней.
class FakeQuestRepository implements QuestRepository {
  FakeQuestRepository({this.delay = const Duration(milliseconds: 700), DateTime? now}) : _now = now;

  final Duration delay;
  final DateTime? _now;

  // orgId, название, описание, сложность, день от сегодня, час, длительность ч, широта, долгота, мест, записано
  static const _seed = [
    ('tq', 'Уборка набережной Ишима', 'Собираем мусор вдоль набережной. Перчатки, мешки и перекус — на месте.', Difficulty.easy, 2, 10, 3, 51.1253, 71.4370, 20, 12),
    ('tq', 'Субботник в центральном парке', 'Убираем аллеи и газоны после выходных.', Difficulty.easy, 5, 11, 2, 51.1480, 71.4100, 25, 9),
    ('tq', 'Сбор пластика у озера', 'Сортируем пластик прямо на месте и сдаём на переработку.', Difficulty.medium, 0, 16, 2, 51.1150, 71.4560, 15, 15),
    ('dl', 'Выгул собак в приюте', 'Гуляем с собаками, которые ждут хозяев.', Difficulty.easy, 1, 12, 2, 51.1490, 71.4020, 10, 6),
    ('dl', 'Уборка вольеров', 'Чистим вольеры и меняем подстилку. Нужна удобная одежда.', Difficulty.medium, 3, 10, 4, 51.1500, 71.3990, 8, 3),
    ('dl', 'Сбор корма у супермаркета', 'Принимаем корм от покупателей у входа.', Difficulty.easy, 6, 14, 3, 51.1590, 71.4240, 6, 2),
    ('kq', 'Раздача продуктовых наборов', 'Фасуем и раздаём наборы семьям.', Difficulty.medium, 2, 9, 5, 51.1010, 71.4210, 15, 15),
    ('kq', 'Помощь пожилым с покупками', 'Доставляем продукты по списку, по двое.', Difficulty.easy, 4, 15, 2, 51.1080, 71.4400, 12, 5),
    ('kq', 'Сортировка одежды', 'Разбираем пожертвованную одежду по размерам.', Difficulty.easy, 8, 11, 3, 51.0980, 71.4150, 10, 4),
    ('ze', 'Посадка деревьев в парке', 'Копаем, сажаем, поливаем. Берите воду и крепкую обувь.', Difficulty.hard, 3, 11, 6, 51.0890, 71.3850, 30, 9),
    ('ze', 'Полив саженцев', 'Поливаем молодые деревья вдоль аллеи.', Difficulty.easy, 0, 18, 2, 51.0920, 71.3950, 10, 4),
    ('ze', 'Клумбы у школы №12', 'Разбиваем клумбы вместе с учениками.', Difficulty.medium, 7, 10, 3, 51.1200, 71.4000, 15, 6),
    ('eo', 'Экоурок для школьников', 'Рассказываем, как сортировать мусор дома.', Difficulty.easy, 1, 15, 2, 51.1600, 71.4700, 6, 2),
    ('eo', 'Помощь на городском фестивале', 'Встречаем гостей и следим за чистотой площадки.', Difficulty.medium, 5, 12, 5, 51.1280, 71.4300, 40, 18),
    ('eo', 'Мастер-класс по переработке', 'Делаем полезные вещи из пластика.', Difficulty.easy, 9, 16, 2, 51.1700, 71.4650, 12, 3),
    ('bv', 'Волонтёры на марафоне', 'Пункты воды и навигация бегунов.', Difficulty.hard, 4, 7, 6, 51.1330, 71.4450, 50, 31),
    ('bv', 'Уборка после матча', 'Убираем трибуны и территорию стадиона.', Difficulty.medium, 6, 21, 2, 51.1080, 71.4030, 20, 7),
    ('bv', 'Детские соревнования', 'Помогаем судьям и следим за порядком.', Difficulty.easy, 2, 10, 4, 51.1450, 71.4600, 12, 5),
  ];

  static const _orgNames = {'tq': 'TazaQala', 'dl': 'Добрые лапы', 'kq': 'Қамқор', 'ze': 'Жасыл Ел', 'eo': 'El Omit', 'bv': 'Bars Volunteers'};
  static const _seniors = ['Данияр С.', 'Айгерим Н.', 'Ерлан М.'];

  List<Quest> all() {
    final now = _now ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    var i = 0;
    return [
      for (final s in _seed)
        Quest(
          id: 'q${++i}',
          orgId: s.$1,
          orgName: _orgNames[s.$1]!,
          title: s.$2,
          description: s.$3,
          difficulty: s.$4,
          // Квест «сегодня» сдвигаем на 2 часа вперёд, чтобы он не оказался в прошлом.
          startsAt: s.$5 == 0 ? now.add(const Duration(hours: 2)) : today.add(Duration(days: s.$5, hours: s.$6)),
          duration: Duration(hours: s.$7),
          location: (lat: s.$8, lng: s.$9),
          address: 'Астана',
          capacity: s.$10,
          joined: s.$11,
          seniorName: _seniors[i % _seniors.length],
        ),
    ];
  }

  @override
  Future<List<Quest>> listForOrg(String orgId) async {
    await Future<void>.delayed(delay);
    return all().where((q) => q.orgId == orgId).toList();
  }

  @override
  Future<List<Quest>> listPublic() async {
    await Future<void>.delayed(delay);
    return all();
  }

  @override
  Future<Quest?> byId(String id) async {
    await Future<void>.delayed(delay);
    return all().where((q) => q.id == id).firstOrNull;
  }
}
