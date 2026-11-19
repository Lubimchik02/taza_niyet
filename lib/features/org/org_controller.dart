import '../../core/backend/backend.dart';
import '../../core/backend/supabase_data.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/geo.dart';
import '../../core/settings/settings_controller.dart';
import 'data/org_repository.dart';

// Сервер, если при сборке заданы SUPABASE_URL и SUPABASE_ANON_KEY; иначе демо.
final orgRepositoryProvider = Provider<OrgRepository>((ref) => Backend.enabled ? SupabaseOrgRepository(ref.watch(prefsProvider)) : FakeOrgRepository(ref.watch(prefsProvider)));
final locationServiceProvider = Provider<LocationService>((ref) => FakeLocationService());

/// Членство пользователя в организации (null — ещё не выбрал).
class MembershipController extends Notifier<Membership?> {
  OrgRepository get _repo => ref.read(orgRepositoryProvider);

  @override
  Membership? build() {
    final m = _repo.saved;
    if (m?.status == MembershipStatus.pending) _listen(m!);
    return m;
  }

  /// Членство с сервера (при запуске и по уведомлению координатора).
  void setFromServer(Membership? m) {
    state = m;
    _repo.save(m);
    if (m?.status == MembershipStatus.pending) _listen(m!);
  }

  Future<void> request(Organization org) async {
    final m = await _repo.requestJoin(org);
    state = m;
    _listen(m);
  }

  void _listen(Membership pending) {
    _repo.awaitDecision(pending).then((m) {
      // Пользователь мог отменить заявку, пока ждал.
      if (state?.orgId == pending.orgId && state?.status == MembershipStatus.pending) state = m;
    });
  }

  Future<void> cancel() async {
    final m = state;
    if (m == null) return;
    await _repo.cancel(m);
    state = null;
  }
}

final membershipProvider = NotifierProvider<MembershipController, Membership?>(MembershipController.new);
