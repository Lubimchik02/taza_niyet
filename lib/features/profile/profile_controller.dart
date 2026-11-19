import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_controller.dart';
import '../auth/auth_controller.dart';
import '../auth/data/validators.dart';
import '../../core/backend/backend.dart';
import '../../core/backend/supabase_data.dart';
import '../shift/shift_controller.dart';
import 'data/portfolio.dart';

final isMinorProvider = Provider<bool>((ref) {
  final y = ref.watch(sessionProvider)?.birthYear;
  return y != null && AuthValidators.isMinor(y);
});

class VisibilityController extends Notifier<HoursVisibility> {
  static const _k = 'profile.hoursVisibility';

  @override
  HoursVisibility build() {
    final minor = ref.watch(isMinorProvider);
    final saved = ref.watch(prefsProvider).getString(_k);
    // По умолчанию: взрослым — «все», до 18 — «друзья».
    final chosen = HoursVisibility.values.where((v) => v.name == saved).firstOrNull ?? (minor ? HoursVisibility.friends : HoursVisibility.everyone);
    return effectiveVisibility(chosen, minor: minor);
  }

  Future<void> set(HoursVisibility v) async {
    state = effectiveVisibility(v, minor: ref.read(isMinorProvider));
    await ref.read(prefsProvider).setString(_k, state.name);
  }
}

final hoursVisibilityProvider = NotifierProvider<VisibilityController, HoursVisibility>(VisibilityController.new);

/// Номер портфолио: на сервере — случайный (можно перевыпустить), в демо — из id пользователя.
final portfolioCodeProvider = FutureProvider<String>((ref) async {
  final u = ref.watch(sessionProvider);
  if (Backend.enabled && u != null) return serverPortfolioCode();
  return portfolioCode(u?.id ?? 'guest');
});

/// Результат проверки номера: null — не найден или отозван.
typedef VerifyResult = ({String name, double hours, int tz, int shifts});

final verifyProvider = FutureProvider.autoDispose.family<VerifyResult?, String>((ref, code) async {
  if (Backend.enabled) {
    final rows = (await Backend.client.rpc('verify_portfolio', params: {'p_code': code}) as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (name: r['name'] as String, hours: (r['hours'] as num).toDouble(), tz: (r['tz'] as num).toInt(), shifts: (r['shifts'] as num).toInt());
  }
  final u = ref.watch(sessionProvider);
  if (u == null || portfolioCode(u.id) != code.toUpperCase()) return null;
  final t = ref.watch(totalsProvider);
  return (name: u.name ?? '', hours: t.hours, tz: t.tz, shifts: ref.watch(creditsProvider).where((c) => c.kind == CreditKind.shift).length);
});
