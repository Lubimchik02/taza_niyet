import 'package:supabase_flutter/supabase_flutter.dart';

/// Подключение к серверу. Адрес и публичный ключ передаются при сборке:
///   flutter run --dart-define=SUPABASE_URL=https://… --dart-define=SUPABASE_ANON_KEY=…
/// Без них приложение работает на демо-данных (Fake-репозитории), как в прототипе.
/// Для запуска в Казахстане адрес — свой сервер Supabase в РК (см. ACCOUNTS.md).
abstract final class Backend {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Адрес возврата после входа через Apple/Google (зарегистрировать в Supabase → Auth → URL Configuration).
  static const authRedirect = 'kz.tazaniyet.app://login-callback';

  static bool get enabled => url.isNotEmpty && anonKey.isNotEmpty;

  static SupabaseClient get client => Supabase.instance.client;

  static Future<void> init() async {
    if (!enabled) return;
    await Supabase.initialize(url: url, anonKey: anonKey);
  }
}
