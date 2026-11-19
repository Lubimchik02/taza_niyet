import '../../core/backend/backend.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings/settings_controller.dart';

/// Переключатели настроек (уведомления, приватность, доступность). Хранятся на устройстве;
/// уведомления и приватность на этапе 12 синхронизируются с сервером.
abstract final class Toggles {
  static const nShifts = 'n.shifts', nChats = 'n.chats', nQuests = 'n.quests', nFriends = 'n.friends', nHours = 'n.hours', nNews = 'n.news', quiet = 'n.quiet';
  static const showInSearch = 'p.search', showInRating = 'p.rating';
  static const reduceMotion = 'a.reduceMotion', haptics = 'a.haptics';

  static const defaults = {
    nShifts: true, nChats: true, nQuests: true, nFriends: true, nHours: true,
    nNews: false, // рекламное/новостное — только по согласию
    quiet: true,
    showInSearch: true, showInRating: true,
    reduceMotion: false, haptics: true,
  };
}

class ToggleController extends FamilyNotifier<bool, String> {
  String get _k => 'toggle.$arg';

  @override
  bool build(String key) => ref.watch(prefsProvider).getBool(_k) ?? Toggles.defaults[key] ?? false;

  Future<void> set(bool v) async {
    state = v;
    await ref.read(prefsProvider).setBool(_k, v);
    // Уведомления соблюдает сервер (функция push) — сохраняем выбор и там.
    if (Backend.enabled && arg.startsWith('n.') && Backend.client.auth.currentUser != null) {
      try {
        final cur = await Backend.client.from('profiles').select('notify').eq('id', Backend.client.auth.currentUser!.id).single();
        await Backend.client.from('profiles').update({'notify': {...(cur['notify'] as Map? ?? {}), arg: v}}).eq('id', Backend.client.auth.currentUser!.id);
      } catch (_) {}
    }
  }
}

final toggleProvider = NotifierProvider.family<ToggleController, bool, String>(ToggleController.new);

/// Масштаб текста поверх системного: 1.0 — как в системе, до 1.5.
class TextScaleController extends Notifier<double> {
  static const _k = 'a.textScale';
  @override
  double build() => ref.watch(prefsProvider).getDouble(_k) ?? 1.0;

  Future<void> set(double v) async {
    state = (v.clamp(1.0, 1.5) * 10).round() / 10;
    await ref.read(prefsProvider).setDouble(_k, state);
  }
}

final textScaleProvider = NotifierProvider<TextScaleController, double>(TextScaleController.new);

enum WhoCanAdd { everyone, myOrg, nobody }

class WhoCanAddController extends Notifier<WhoCanAdd> {
  static const _k = 'p.whoCanAdd';
  @override
  WhoCanAdd build() => WhoCanAdd.values.where((v) => v.name == ref.watch(prefsProvider).getString(_k)).firstOrNull ?? WhoCanAdd.everyone;

  Future<void> set(WhoCanAdd v) async {
    state = v;
    await ref.read(prefsProvider).setString(_k, v.name);
  }
}

final whoCanAddProvider = NotifierProvider<WhoCanAddController, WhoCanAdd>(WhoCanAddController.new);

/// Сеанс входа на устройстве.
@immutable
class DeviceSession {
  const DeviceSession({required this.id, required this.device, required this.place, required this.lastActive, this.current = false});
  final String id, device, place;
  final DateTime lastActive;
  final bool current;
}

/// Активные сеансы. Реальный — Supabase Auth: список refresh-токенов, отзыв (этап 12).
class SessionsController extends Notifier<List<DeviceSession>> {
  @override
  List<DeviceSession> build() {
    final now = DateTime.now();
    return [
      DeviceSession(id: 's1', device: defaultTargetPlatform == TargetPlatform.iOS ? 'iPhone' : 'Android', place: 'Астана', lastActive: now, current: true),
      DeviceSession(id: 's2', device: 'iPad', place: 'Астана', lastActive: now.subtract(const Duration(days: 2))),
      DeviceSession(id: 's3', device: 'Samsung Galaxy A54', place: 'Алматы', lastActive: now.subtract(const Duration(days: 9))),
    ];
  }

  Future<void> end(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    state = state.where((s) => s.id != id || s.current).toList();
  }

  Future<void> endOthers() async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    state = state.where((s) => s.current).toList();
  }
}

final sessionsProvider = NotifierProvider<SessionsController, List<DeviceSession>>(SessionsController.new);

/// Демо: двухфакторная защита и ключи доступа (в реальном — Supabase Auth MFA / WebAuthn).
final twoFactorProvider = StateProvider<bool>((ref) => false);
final passkeysProvider = StateProvider<int>((ref) => 0);
