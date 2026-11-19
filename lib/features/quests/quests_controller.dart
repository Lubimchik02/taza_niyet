import '../../core/backend/backend.dart';
import '../../core/backend/supabase_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/net/connectivity.dart';
import '../org/data/org_repository.dart';
import '../org/org_controller.dart';
import 'data/quest_repository.dart';

// Сервер, если при сборке заданы SUPABASE_URL и SUPABASE_ANON_KEY; иначе демо.
final questRepositoryProvider = Provider<QuestRepository>((ref) => Backend.enabled ? SupabaseQuestRepository() : FakeQuestRepository());

/// Квесты своей организации; без организации (или пока заявка не одобрена) — все квесты города
/// только для просмотра. Перезагружаются при смене организации.
final questsProvider = FutureProvider.autoDispose<List<Quest>>((ref) async {
  final m = ref.watch(membershipProvider);
  final repo = ref.read(questRepositoryProvider);
  final last = ref.read(lastQuestsProvider);
  // Без сети показываем последний загруженный список (на устройстве — до этапа 12, где будет SQLite-кэш).
  if (!ref.watch(isOnlineProvider) && last != null) return last;
  final list = (m == null || m.status == MembershipStatus.rejected) ? await repo.listPublic() : await repo.listForOrg(m.orgId);
  ref.read(lastQuestsProvider.notifier).state = list;
  return list;
});

final lastQuestsProvider = StateProvider<List<Quest>?>((ref) => null);

class QuestFilterController extends Notifier<QuestFilter> {
  @override
  QuestFilter build() => const QuestFilter();

  void set(QuestFilter f) => state = f;
  void reset() => state = const QuestFilter();
}

final questFilterProvider = NotifierProvider<QuestFilterController, QuestFilter>(QuestFilterController.new);
