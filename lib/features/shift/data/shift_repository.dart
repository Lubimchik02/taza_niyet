import 'package:flutter/foundation.dart';

import '../../../core/geo.dart';
import '../../quests/data/quest_repository.dart';
import '../../quests/data/signup_repository.dart';

/// Отметиться можно за 30 минут до начала и до конца квеста.
const kCheckInEarly = Duration(minutes: 30);

/// Геометка засчитывается в радиусе 300 м от места сбора.
const kCheckInRadiusKm = 0.3;

/// Старшему за точный учёт после подтверждения координатором.
const kSeniorBonusTz = 10;

enum CheckInWindow { notYet, open, ended }

CheckInWindow checkInWindow(Quest q, DateTime now) {
  if (now.isBefore(q.startsAt.subtract(kCheckInEarly))) return CheckInWindow.notYet;
  if (now.isAfter(q.endsAt)) return CheckInWindow.ended;
  return CheckInWindow.open;
}

/// Баллы за часы: 1 ч = 5 Tz.
int tzForHours(double hours) => (hours * 5).round();

/// Часы нельзя завысить: от 0 до длительности квеста, шаг 0,5 ч.
double clampHours(double h, Quest q) {
  final max = q.duration.inMinutes / 60;
  return ((h.clamp(0, max)) * 2).round() / 2;
}

/// Результат «Я на месте».
sealed class CheckInResult {
  const CheckInResult();
}

class CheckedIn extends CheckInResult {
  const CheckedIn({required this.at, required this.geoVerified});
  final DateTime at;
  final bool geoVerified;
}

class TooFar extends CheckInResult {
  const TooFar(this.km);
  final double km;
}

class NeedsLocation extends CheckInResult {
  const NeedsLocation();
}

/// Проверка отметки — чистая функция: где человек и где квест.
CheckInResult evaluateCheckIn({required Quest quest, required LatLng? me, required DateTime now, bool force = false}) {
  if (quest.checkInAnywhere) return CheckedIn(at: now, geoVerified: true);
  if (me == null) return force ? CheckedIn(at: now, geoVerified: false) : const NeedsLocation();
  final km = distanceKm(me, quest.location);
  if (km <= kCheckInRadiusKm) return CheckedIn(at: now, geoVerified: true);
  return force ? CheckedIn(at: now, geoVerified: false) : TooFar(km);
}

/// Участник команды в списке старшего.
@immutable
class RosterMember {
  const RosterMember({required this.id, required this.name, this.checkedInAt, this.geoVerified = false, this.markedBySenior = false, required this.hours, this.isMe = false, this.minor = false});

  final String id, name;
  final DateTime? checkedInAt;
  final bool geoVerified, markedBySenior, isMe, minor;
  final double hours;

  bool get present => checkedInAt != null || markedBySenior;

  RosterMember copyWith({bool? markedBySenior, double? hours}) => RosterMember(
        id: id, name: name, checkedInAt: checkedInAt, geoVerified: geoVerified,
        markedBySenior: markedBySenior ?? this.markedBySenior, hours: hours ?? this.hours, isMe: isMe, minor: minor,
      );
}

/// Отчёт старшего о смене. Ручные отметки и изменённые часы координатор видит отдельно.
@immutable
class ShiftReport {
  const ShiftReport({required this.questId, required this.teamId, required this.members});
  final String questId, teamId;
  final List<RosterMember> members;

  int get presentCount => members.where((m) => m.present).length;
  int get absentCount => members.length - presentCount;
  double get totalHours => members.where((m) => m.present).fold(0, (a, m) => a + m.hours);
  int get manualCount => members.where((m) => m.markedBySenior && m.checkedInAt == null).length;
}

enum ReportStatus { sent, approved }

/// Контракт. Реальный — Supabase: check_ins, shift_reports, ledger; одобрение — в веб-кабинете
/// координатора; начисление — серверная функция (этап 12).
abstract interface class ShiftRepository {
  /// «Я на месте» на сервер (время — с телефона; из офлайн-очереди может прийти позже).
  Future<void> checkIn(Quest q, {LatLng? at, required DateTime time});

  /// Старший отмечает пришедшего вручную (или снимает свою отметку).
  Future<void> markPresent(Quest q, String userId, bool present);

  Future<List<RosterMember>> roster(Quest q, Team team, {required String myName, Signup? mine});
  Future<void> submit(ShiftReport report);
  Future<ReportStatus> awaitApproval(ShiftReport report);
}

class FakeShiftRepository implements ShiftRepository {
  FakeShiftRepository({this.delay = const Duration(milliseconds: 500), this.decision = const Duration(seconds: 4)});
  final Duration delay, decision;

  static const _names = ['Алия Б.', 'Тимур К.', 'Дана С.', 'Ержан А.', 'Камила Р.', 'Нурсултан Ж.', 'Аружан М.', 'Санжар Е.', 'Мира О.'];

  @override
  Future<List<RosterMember>> roster(Quest q, Team team, {required String myName, Signup? mine}) async {
    await Future<void>.delayed(delay);
    final h = q.duration.inMinutes / 60;
    final others = (team.joined - (mine != null ? 1 : 0)).clamp(0, _names.length);
    return [
      if (mine != null)
        RosterMember(id: 'me', name: myName, isMe: true, checkedInAt: mine.checkedInAt, geoVerified: mine.geoVerified, hours: h),
      for (var i = 0; i < others; i++)
        RosterMember(
          id: 'm$i',
          name: _names[i],
          // Демо: большинство уже отметились сами, двое — нет.
          checkedInAt: i % 4 == 3 ? null : q.startsAt.add(Duration(minutes: i * 3 - 10)),
          geoVerified: i % 4 != 2,
          hours: h,
          minor: i == 1,
        ),
    ];
  }

  @override
  Future<void> checkIn(Quest q, {LatLng? at, required DateTime time}) async {}

  @override
  Future<void> markPresent(Quest q, String userId, bool present) async {}

  @override
  Future<void> submit(ShiftReport report) => Future<void>.delayed(delay);

  @override
  Future<ReportStatus> awaitApproval(ShiftReport report) async {
    await Future<void>.delayed(decision);
    return ReportStatus.approved;
  }
}
