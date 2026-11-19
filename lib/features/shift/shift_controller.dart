import '../../core/backend/backend.dart';
import '../../core/backend/supabase_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geo.dart';
import '../../core/net/connectivity.dart';
import '../notifications/notifications.dart';
import '../offline/outbox.dart';
import '../org/org_controller.dart';
import '../quests/data/signup_repository.dart';
import '../quests/signups_controller.dart';
import 'data/shift_repository.dart';

// Сервер, если при сборке заданы SUPABASE_URL и SUPABASE_ANON_KEY; иначе демо.
final shiftRepositoryProvider = Provider<ShiftRepository>((ref) => Backend.enabled ? SupabaseShiftRepository() : FakeShiftRepository());

/// Демо-переключатель «я старший». В реальном приложении роль приходит с сервера
/// (координатор назначает старшего команды) — этап 12.
final seniorModeProvider = StateProvider<bool>((ref) => false);

enum CreditKind { shift, seniorBonus }

/// Начисление: часы и баллы за смену или бонус старшему.
@immutable
class Credit {
  const Credit({required this.questTitle, required this.date, required this.hours, required this.tz, required this.kind, this.orgName = ''});
  final String questTitle, orgName;
  final DateTime date;
  final double hours;
  final int tz;
  final CreditKind kind;
}

/// Подтверждённые часы и баллы (основа портфолио — этап 8).
class CreditsController extends Notifier<List<Credit>> {
  @override
  List<Credit> build() => const [];
  void add(Credit c) => state = [c, ...state];

  /// Полный список с сервера (источник правды — журнал credits).
  void replaceAll(List<Credit> list) => state = list;
}

final creditsProvider = NotifierProvider<CreditsController, List<Credit>>(CreditsController.new);

final totalsProvider = Provider<({double hours, int tz})>((ref) {
  final all = ref.watch(creditsProvider);
  return (hours: all.fold(0.0, (a, c) => a + c.hours), tz: all.fold(0, (a, c) => a + c.tz));
});

/// Статус отчёта старшего по квесту: questId → отправлен / подтверждён.
class ShiftController extends Notifier<Map<String, ReportStatus>> {
  @override
  Map<String, ReportStatus> build() => const {};

  ShiftRepository get _repo => ref.read(shiftRepositoryProvider);
  MySignupsController get _signups => ref.read(mySignupsProvider.notifier);

  /// «Я на месте». [force] — отметиться без геометки (подтвердит старший).
  Future<CheckInResult> checkIn(Signup s, {bool force = false}) async {
    final loc = ref.read(locationServiceProvider);
    if (loc.permission != LocationPermission.granted && !force) {
      if (await loc.request() != LocationPermission.granted) return const NeedsLocation();
    }
    final me = await loc.current();
    final r = evaluateCheckIn(quest: s.quest, me: me, now: DateTime.now(), force: force);
    if (r is CheckedIn) {
      _signups.replace(s.copyWith(checkedInAt: r.at, geoVerified: r.geoVerified));
      // Нет сети на месте — отметка (время + геометка) ждёт в очереди и уйдёт позже.
      final item = OutboxItem(id: 'ci-${s.quest.id}', type: 'checkin', ref: s.quest.id, at: r.at, payload: {'geo': r.geoVerified, 'lat': me?.lat, 'lng': me?.lng});
      if (!ref.read(isOnlineProvider)) {
        await ref.read(outboxProvider.notifier).add(item);
      } else {
        try {
          await _repo.checkIn(s.quest, at: me, time: r.at);
        } catch (_) {
          await ref.read(outboxProvider.notifier).add(item); // сеть пропала посреди запроса
        }
      }
    }
    return r;
  }

  /// Старший закрывает смену: отчёт уходит координатору, после одобрения — начисления.
  Future<void> close(ShiftReport report, {required String questTitle, required DateTime date, String orgName = ''}) async {
    await _repo.submit(report);
    state = {...state, report.questId: ReportStatus.sent};
    final me = report.members.where((m) => m.isMe).firstOrNull;
    _mark(report.questId, me, ShiftState.reported);
    final status = await _repo.awaitApproval(report);
    state = {...state, report.questId: status};
    _mark(report.questId, me, ShiftState.approved);
    final credits = ref.read(creditsProvider.notifier);
    _notify(questTitle, report.questId, me != null && me.present ? tzForHours(me.hours) + kSeniorBonusTz : kSeniorBonusTz);
    if (me != null && me.present && me.hours > 0) {
      credits.add(Credit(questTitle: questTitle, date: date, hours: me.hours, tz: tzForHours(me.hours), kind: CreditKind.shift, orgName: orgName));
    }
    credits.add(Credit(questTitle: questTitle, date: date, hours: 0, tz: kSeniorBonusTz, kind: CreditKind.seniorBonus, orgName: orgName));
  }

  /// Демо для обычного волонтёра: старший закрыл смену, координатор подтвердил.
  Future<void> simulateSeniorClose(Signup s) async {
    final hours = s.checkedInAt == null ? 0.0 : clampHours(s.quest.duration.inMinutes / 60, s.quest);
    _signups.replace(s.copyWith(shift: hours == 0 ? ShiftState.missed : ShiftState.reported, hours: hours));
    if (hours == 0) return;
    await Future<void>.delayed(const Duration(seconds: 4));
    final cur = _signups.forQuest(s.quest.id);
    if (cur == null) return;
    _signups.replace(cur.copyWith(shift: ShiftState.approved));
    _notify(s.quest.title, s.quest.id, tzForHours(hours));
    ref.read(creditsProvider.notifier).add(Credit(questTitle: s.quest.title, date: s.start, hours: hours, tz: tzForHours(hours), kind: CreditKind.shift, orgName: s.quest.orgName));
  }

  /// Текст уведомления строится на экране (локализация); здесь — данные и адрес перехода.
  void _notify(String questTitle, String questId, int tz) =>
      ref.read(inboxProvider.notifier).add(kind: NotifKind.hoursApproved, body: questTitle, route: '/profile/portfolio', args: {'tz': '$tz'});

  void _mark(String questId, RosterMember? me, ShiftState st) {
    final s = _signups.forQuest(questId);
    if (s == null || me == null) return;
    _signups.replace(s.copyWith(shift: me.present ? st : ShiftState.missed, hours: me.present ? me.hours : 0));
  }
}

final shiftControllerProvider = NotifierProvider<ShiftController, Map<String, ReportStatus>>(ShiftController.new);
