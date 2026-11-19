import '../../core/backend/backend.dart';
import '../../core/backend/supabase_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geo.dart';
import '../notifications/notifications.dart';
import '../org/org_controller.dart';
import 'data/quest_repository.dart';
import 'data/signup_repository.dart';
import 'quests_controller.dart';

// Сервер, если при сборке заданы SUPABASE_URL и SUPABASE_ANON_KEY; иначе демо.
final signupRepositoryProvider = Provider<SignupRepository>((ref) => Backend.enabled ? SupabaseSignupRepository() : FakeSignupRepository());

/// Мои записи (в командах и в листах ожидания), по времени начала.
class MySignupsController extends Notifier<List<Signup>> {
  @override
  List<Signup> build() => const [];

  SignupRepository get _repo => ref.read(signupRepositoryProvider);

  /// Записи с сервера (при запуске).
  void replaceAll(List<Signup> list) => state = [...list]..sort((a, b) => a.start.compareTo(b.start));

  Signup? forQuest(String questId) => state.where((s) => s.quest.id == questId).firstOrNull;

  Future<Signup> join(Quest q, {Team? team}) async {
    final s = await _repo.join(q, team: team, mine: state);
    state = [...state, s]..sort((a, b) => a.start.compareTo(b.start));
    ref.invalidate(teamsProvider(q.id));
    return s;
  }

  /// Обновить запись (отметка на месте, итоги смены).
  void replace(Signup s) => state = [for (final x in state) x.quest.id == s.quest.id ? s : x];

  /// Демо: перенести начало квеста на «5 минут назад» и «встать» на место сбора,
  /// чтобы проверить отметку и закрытие смены, не дожидаясь даты квеста.
  void demoStartNow(String questId) {
    final s = forQuest(questId);
    if (s == null) return;
    replace(s.copyWith(quest: s.quest.copyWith(startsAt: DateTime.now().subtract(const Duration(minutes: 5)))));
    final loc = ref.read(locationServiceProvider);
    if (loc is FakeLocationService) loc.demoPosition = s.quest.location;
  }

  Future<void> leave(Signup s) async {
    await _repo.leave(s);
    ref.read(localNotificationsProvider).cancelShift(s.quest.id);
    state = state.where((x) => x.quest.id != s.quest.id).toList();
    ref.invalidate(teamsProvider(s.quest.id));
  }
}

final mySignupsProvider = NotifierProvider<MySignupsController, List<Signup>>(MySignupsController.new);

/// Квест по id: сначала из загруженного списка, иначе с сервера (ссылка-приглашение).
final questByIdProvider = FutureProvider.autoDispose.family<Quest?, String>((ref, id) async {
  final listed = ref.watch(questsProvider).valueOrNull?.where((q) => q.id == id).firstOrNull;
  return listed ?? ref.read(questRepositoryProvider).byId(id);
});

final teamsProvider = FutureProvider.autoDispose.family<List<Team>, String>((ref, questId) async {
  final q = await ref.watch(questByIdProvider(questId).future);
  if (q == null) return const [];
  return ref.read(signupRepositoryProvider).teams(q);
});
