import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../core/backend/backend.dart';
import '../../core/settings/settings_controller.dart';
import '../quests/data/quest_repository.dart';
import '../settings/settings_prefs.dart';

enum NotifKind { reminder, hoursApproved, friend, org, chat, system }

/// Уведомление во входящих (колокольчик на главной). Пуш с сервера (FCM/APNs) кладёт сюда же
/// и открывает [route] по нажатию — тот же адрес, что у ссылки tazaniyet.kz/...
@immutable
class AppNotification {
  const AppNotification({required this.id, required this.kind, required this.title, this.body = '', this.route, required this.at, this.read = false, this.args = const {}});
  final String id, title, body;

  /// Данные для локализованного заголовка (текст строится на экране на текущем языке).
  final Map<String, String> args;
  final NotifKind kind;
  final String? route;
  final DateTime at;
  final bool read;

  AppNotification markRead() => AppNotification(id: id, kind: kind, title: title, body: body, route: route, at: at, read: true, args: args);
}

class InboxController extends Notifier<List<AppNotification>> {
  @override
  List<AppNotification> build() => const [];

  void add({required NotifKind kind, String title = '', String body = '', String? route, Map<String, String> args = const {}}) {
    state = [AppNotification(id: '${DateTime.now().microsecondsSinceEpoch}', kind: kind, title: title, body: body, route: route, at: DateTime.now(), args: args), ...state].take(100).toList();
  }

  /// С сервера: полный список и новые в реальном времени.
  void replaceAll(List<AppNotification> list) => state = list;
  void push(AppNotification n) => state = [n, ...state.where((x) => x.id != n.id)].take(100).toList();

  void read(String id) {
    state = [for (final n in state) n.id == id ? n.markRead() : n];
    if (Backend.enabled) Backend.client.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).eq('id', id).then((_) {}, onError: (_) {});
  }

  void readAll() {
    state = [for (final n in state) n.markRead()];
    if (Backend.enabled) {
      Backend.client.from('notifications').update({'read_at': DateTime.now().toUtc().toIso8601String()}).isFilter('read_at', null).then((_) {}, onError: (_) {});
    }
  }
}

final inboxProvider = NotifierProvider<InboxController, List<AppNotification>>(InboxController.new);
final unreadNotificationsProvider = Provider<int>((ref) => ref.watch(inboxProvider).where((n) => !n.read).length);

/// Время напоминаний о смене: за 24 ч и за 1 ч. Прошедшие — пропускаем.
List<DateTime> reminderTimes(Quest q, DateTime now) => [
      q.startsAt.subtract(const Duration(days: 1)),
      q.startsAt.subtract(const Duration(hours: 1)),
    ].where((t) => t.isAfter(now)).toList();

/// Локальные напоминания (работают и без сети). Серверные пуши — FCM, этап 12.
class LocalNotifications {
  LocalNotifications(this._ref);
  final Ref _ref;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _kAsked = 'push.asked';

  bool get asked => _ref.read(prefsProvider).getBool(_kAsked) ?? false;

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Almaty')); // Казахстан: UTC+5 с 2024 г.
    await _plugin.initialize(const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
    ));
    _ready = true;
  }

  /// Системный запрос — только после нашего объяснения (мягкий запрос) и только один раз.
  Future<bool> requestPermission() async {
    await _init();
    await _ref.read(prefsProvider).setBool(_kAsked, true);
    final ios = await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(alert: true, badge: true, sound: true);
    final android = await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
    return ios ?? android ?? false;
  }

  Future<void> markAsked() => _ref.read(prefsProvider).setBool(_kAsked, true);

  int _id(String questId, int i) => (questId.hashCode & 0x0fffffff) * 2 + i;

  Future<void> scheduleShift(Quest q, {required String dayText, required String hourText}) async {
    if (!_ref.read(toggleProvider(Toggles.nShifts))) return;
    try {
      await _init();
      final times = reminderTimes(q, DateTime.now());
      for (final (i, t) in times.indexed) {
        await _plugin.zonedSchedule(
          _id(q.id, i),
          'Taza Niyet',
          t.difference(q.startsAt).inHours.abs() >= 24 ? dayText : hourText,
          tz.TZDateTime.from(t, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails('shifts', 'Смены', importance: Importance.high, priority: Priority.high),
            iOS: DarwinNotificationDetails(interruptionLevel: InterruptionLevel.timeSensitive),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          payload: '/quest/${q.id}',
        );
      }
    } catch (e) {
      debugPrint('Напоминание не запланировано: $e'); // например, в тестах или без разрешения
    }
  }

  Future<void> cancelShift(String questId) async {
    try {
      await _init();
      await _plugin.cancel(_id(questId, 0));
      await _plugin.cancel(_id(questId, 1));
    } catch (_) {}
  }
}

final localNotificationsProvider = Provider<LocalNotifications>((ref) => LocalNotifications(ref));
