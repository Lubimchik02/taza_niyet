import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../core/backend/backend.dart';

/// Серверные пуши (FCM, на iOS — через APNs). Нужны файлы google-services.json и
/// GoogleService-Info.plist (см. ACCOUNTS.md); без них сервис тихо не запускается.
/// Разрешение спрашивает мягкий запрос после первой записи (LocalNotifications.requestPermission).
abstract final class PushService {
  static bool _started = false;

  static Future<void> start(GoRouter router) async {
    if (_started || !Backend.enabled || Backend.client.auth.currentUser == null) return;
    try {
      await Firebase.initializeApp();
      final fm = FirebaseMessaging.instance;
      Future<void> save(String? token) async {
        if (token == null) return;
        await Backend.client.rpc('register_push_token', params: {'p_token': token, 'p_platform': Platform.isIOS ? 'ios' : 'android'});
      }

      await save(await fm.getToken());
      fm.onTokenRefresh.listen(save);
      // Нажатие на пуш открывает нужный экран — тот же адрес, что в уведомлении во входящих.
      void open(RemoteMessage m) {
        final route = m.data['route'] as String?;
        if (route != null && route.startsWith('/')) router.push(route);
      }

      FirebaseMessaging.onMessageOpenedApp.listen(open);
      final initial = await fm.getInitialMessage();
      if (initial != null) open(initial);
      // Пока приложение открыто, пуш не показываем: уведомление уже пришло во входящие через Realtime.
      _started = true;
    } catch (e) {
      debugPrint('Пуши не запущены: $e');
    }
  }
}
