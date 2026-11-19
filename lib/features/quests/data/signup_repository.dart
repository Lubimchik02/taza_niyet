import 'package:flutter/foundation.dart';

import 'quest_repository.dart';

/// Команда квеста. Каждую ведёт старший волонтёр; в команде до 10 человек.
@immutable
class Team {
  const Team({required this.id, required this.number, required this.seniorName, required this.capacity, required this.joined});

  final String id;
  final int number;
  final String seniorName;
  final int capacity, joined;

  int get spotsLeft => (capacity - joined).clamp(0, capacity);
  bool get isFull => spotsLeft == 0;
}

enum SignupStatus { joined, waitlist }

/// Как прошла смена для волонтёра.
enum ShiftState {
  /// Смена ещё не закрыта старшим.
  open,

  /// Старший закрыл смену — ждём координатора.
  reported,

  /// Координатор подтвердил — часы и Tz начислены.
  approved,

  /// Старший не отметил волонтёра (не пришёл).
  missed,
}

/// Запись волонтёра на квест: в команду или в лист ожидания (если мест нет во всём квесте).
@immutable
class Signup {
  const Signup({
    required this.quest,
    required this.status,
    this.team,
    this.position = 0,
    this.checkedInAt,
    this.geoVerified = false,
    this.shift = ShiftState.open,
    this.hours = 0,
  });

  final Quest quest;
  final SignupStatus status;
  final Team? team;

  /// Место в листе ожидания (с 1). Для записанных — 0.
  final int position;

  /// Когда волонтёр нажал «Я на месте».
  final DateTime? checkedInAt;

  /// true — отметка подтверждена геопозицией (до 300 м от места); false — подтвердит старший.
  final bool geoVerified;

  final ShiftState shift;

  /// Засчитанные часы (после закрытия смены).
  final double hours;

  DateTime get start => quest.startsAt;
  DateTime get end => quest.endsAt;

  Signup copyWith({Quest? quest, DateTime? checkedInAt, bool? geoVerified, ShiftState? shift, double? hours}) => Signup(
        quest: quest ?? this.quest,
        status: status,
        team: team,
        position: position,
        checkedInAt: checkedInAt ?? this.checkedInAt,
        geoVerified: geoVerified ?? this.geoVerified,
        shift: shift ?? this.shift,
        hours: hours ?? this.hours,
      );
}

enum SignupFailureKind { timeConflict, alreadySigned, notMember, network }

class SignupFailure implements Exception {
  const SignupFailure(this.kind);
  final SignupFailureKind kind;
  @override
  String toString() => 'SignupFailure($kind)';
}

/// Делим места квеста на команды по 10 и заполняем по порядку.
List<Team> splitIntoTeams(Quest q, {List<String> seniors = const ['Мадина К.', 'Арман Т.', 'Алия Б.', 'Нурлан Ж.', 'Сабина Е.']}) {
  final n = (q.capacity / 10).ceil().clamp(1, 5);
  var left = q.joined;
  return [
    for (var i = 0; i < n; i++)
      () {
        final cap = q.capacity ~/ n + (i < q.capacity % n ? 1 : 0);
        final joined = left.clamp(0, cap);
        left -= joined;
        return Team(id: '${q.id}-t${i + 1}', number: i + 1, seniorName: i == 0 ? q.seniorName : seniors[(i + (int.tryParse(q.id.substring(1)) ?? 0)) % seniors.length], capacity: cap, joined: joined);
      }(),
  ];
}

/// Пересекаются ли два квеста по времени (запись на оба сразу запрещена).
bool overlaps(Quest a, Quest b) => a.startsAt.isBefore(b.startsAt.add(b.duration)) && b.startsAt.isBefore(a.startsAt.add(a.duration));

/// Контракт. Реальный — Supabase: таблицы teams / signups / waitlist, RLS по организации,
/// проверки мест и пересечений — в функции на сервере (этап 12).
abstract interface class SignupRepository {
  Future<List<Team>> teams(Quest q);
  Future<Signup> join(Quest q, {Team? team, required List<Signup> mine});
  Future<void> leave(Signup s);
}

class FakeSignupRepository implements SignupRepository {
  FakeSignupRepository({this.delay = const Duration(milliseconds: 600)});

  final Duration delay;
  final _extra = <String, int>{}; // teamId → наши записи сверх исходных
  final _waiting = <String, int>{}; // questId → длина листа ожидания

  @override
  Future<List<Team>> teams(Quest q) async {
    await Future<void>.delayed(delay ~/ 2);
    return [
      for (final t in splitIntoTeams(q))
        Team(id: t.id, number: t.number, seniorName: t.seniorName, capacity: t.capacity, joined: (t.joined + (_extra[t.id] ?? 0)).clamp(0, t.capacity)),
    ];
  }

  @override
  Future<Signup> join(Quest q, {Team? team, required List<Signup> mine}) async {
    await Future<void>.delayed(delay);
    if (q.title.startsWith('!')) throw const SignupFailure(SignupFailureKind.network); // демо ошибки сети
    if (mine.any((s) => s.quest.id == q.id)) throw const SignupFailure(SignupFailureKind.alreadySigned);
    if (mine.any((s) => s.status == SignupStatus.joined && overlaps(s.quest, q))) throw const SignupFailure(SignupFailureKind.timeConflict);
    final teams = await this.teams(q);
    final free = team == null ? teams.where((t) => !t.isFull).firstOrNull : teams.firstWhere((t) => t.id == team.id);
    if (free == null || free.isFull) {
      // Мест нет нигде — лист ожидания. У заполненных квестов в демо уже ждут двое.
      final pos = (_waiting[q.id] ?? 2) + 1;
      _waiting[q.id] = pos;
      return Signup(quest: q, status: SignupStatus.waitlist, position: pos);
    }
    _extra[free.id] = (_extra[free.id] ?? 0) + 1;
    return Signup(quest: q, status: SignupStatus.joined, team: Team(id: free.id, number: free.number, seniorName: free.seniorName, capacity: free.capacity, joined: free.joined + 1));
  }

  @override
  Future<void> leave(Signup s) async {
    await Future<void>.delayed(delay ~/ 2);
    if (s.team != null) _extra[s.team!.id] = (_extra[s.team!.id] ?? 1) - 1;
    if (s.status == SignupStatus.waitlist) _waiting[s.quest.id] = (_waiting[s.quest.id] ?? 1) - 1;
  }
}
