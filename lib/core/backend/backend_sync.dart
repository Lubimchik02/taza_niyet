import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/notifications/notifications.dart';
import '../../features/org/org_controller.dart';
import '../../features/people/people_controller.dart';
import '../../features/quests/quests_controller.dart';
import '../../features/quests/signups_controller.dart';
import '../../features/shift/shift_controller.dart';
import '../config/app_config.dart';
import 'backend.dart';
import 'supabase_data.dart';

/// Серверное → локальное: при входе и по уведомлениям в реальном времени.
/// Источник правды — сервер; локальные провайдеры — кэш для экрана и офлайна.
class BackendSync {
  BackendSync(this._ref);
  final Ref _ref;
  RealtimeChannel? _channel;

  SupabaseClient get _db => Backend.client;

  Future<void> start() async {
    if (!Backend.enabled || _db.auth.currentUser == null) return;
    await Future.wait([config(), membership(), credits(), signups(), friends(), inbox()]);
    _listen();
  }

  Future<void> stop() async {
    await _channel?.unsubscribe();
    _channel = null;
  }

  Future<void> _safe(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      debugPrint('Синхронизация: $e'); // нет сети — останутся данные из кэша
    }
  }

  Future<void> config() => _safe(() async {
        final rows = (await _db.from('app_config').select() as List).cast<Map<String, dynamic>>();
        final v = {for (final r in rows) r['key'] as String: r['value']};
        _ref.read(appConfigProvider.notifier).set(AppConfig(
              minVersion: v['min_version'] as String? ?? '1.0.0',
              latestVersion: v['latest_version'] as String? ?? '1.0.0',
              flags: (v['flags'] as Map?)?.map((k, x) => MapEntry(k as String, x as bool)) ?? const {},
            ));
      });

  Future<void> membership() => _safe(() async {
        final m = await (_ref.read(orgRepositoryProvider) as SupabaseOrgRepository).refresh();
        _ref.read(membershipProvider.notifier).setFromServer(m);
      });

  Future<void> credits() => _safe(() async {
        final rows = (await _db.from('credits').select('kind, hours, tz, quest_title, org_name, shift_date').eq('user_id', _db.auth.currentUser!.id).order('created_at', ascending: false) as List)
            .cast<Map<String, dynamic>>();
        _ref.read(creditsProvider.notifier).replaceAll([
          for (final r in rows)
            Credit(
              questTitle: r['quest_title'] as String,
              orgName: r['org_name'] as String,
              date: DateTime.parse(r['shift_date'] as String),
              hours: (r['hours'] as num).toDouble(),
              tz: (r['tz'] as num).toInt(),
              kind: r['kind'] == 'shift' ? CreditKind.shift : CreditKind.seniorBonus, // штраф учитывается в сумме Tz
            ),
        ]);
      });

  Future<void> signups() => _safe(() async {
        final known = _ref.read(lastQuestsProvider) ?? const [];
        final list = await (_ref.read(signupRepositoryProvider) as SupabaseSignupRepository).mine(known);
        _ref.read(mySignupsProvider.notifier).replaceAll(list);
      });

  Future<void> friends() => _safe(() => _ref.read(friendsProvider.notifier).sync());

  Future<void> inbox() => _safe(() async {
        final rows = (await _db.from('notifications').select().order('created_at', ascending: false).limit(100) as List).cast<Map<String, dynamic>>();
        _ref.read(inboxProvider.notifier).replaceAll([for (final r in rows) fromServer(r)]);
      });

  /// Новые уведомления — сразу во входящие и, по типу, обновить нужные данные.
  void _listen() {
    final me = _db.auth.currentUser!.id;
    _channel = _db
        .channel('notifications:$me')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: me),
          callback: (p) {
            final n = fromServer(p.newRecord);
            _ref.read(inboxProvider.notifier).push(n);
            switch (p.newRecord['kind']) {
              case 'hours_approved' || 'penalty':
                credits();
                signups();
              case 'org_approved' || 'org_rejected':
                membership();
                _ref.invalidate(questsProvider);
              case 'friend_request' || 'friend_accepted':
                friends();
              case 'waitlist_promoted':
                signups();
            }
          },
        )
        .subscribe();
  }

  static AppNotification fromServer(Map<String, dynamic> r) {
    final args = (r['args'] as Map?)?.map((k, v) => MapEntry(k as String, '$v')) ?? const <String, String>{};
    final kind = switch (r['kind']) {
      'hours_approved' => NotifKind.hoursApproved,
      'friend_accepted' || 'friend_request' => NotifKind.friend,
      'org_approved' || 'org_rejected' => NotifKind.org,
      'chat' => NotifKind.chat,
      'waitlist_promoted' || 'reminder' => NotifKind.reminder,
      _ => NotifKind.system,
    };
    return AppNotification(
      id: r['id'] as String,
      kind: kind,
      title: kind == NotifKind.chat ? '${args['name']}: ${args['text']}' : (args['quest'] ?? args['org'] ?? ''),
      body: args['quest'] ?? '',
      route: r['route'] as String?,
      at: DateTime.parse(r['created_at'] as String).toLocal(),
      read: r['read_at'] != null,
      args: {...args, 'kind': r['kind'] as String},
    );
  }
}

final backendSyncProvider = Provider<BackendSync>((ref) {
  final s = BackendSync(ref);
  ref.onDispose(s.stop);
  return s;
});

/// Запуск синхронизации при входе и остановка при выходе.
final backendSessionProvider = Provider<void>((ref) {
  if (!Backend.enabled) return;
  final user = ref.watch(sessionProvider);
  final sync = ref.read(backendSyncProvider);
  if (user != null && !user.needsProfile) {
    Future.microtask(sync.start);
  } else {
    Future.microtask(sync.stop);
  }
});
