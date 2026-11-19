import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Удалённая конфигурация: минимальная/последняя версия и флаги функций.
/// Реальная — таблица app_config в Supabase (кэшируется на устройстве), этап 12.
@immutable
class AppConfig {
  const AppConfig({this.minVersion = '1.0.0', this.latestVersion = '1.0.0', this.flags = const {}, this.storeUrl = 'https://tazaniyet.kz/app'});
  final String minVersion, latestVersion, storeUrl;
  final Map<String, bool> flags;

  bool flag(String name) => flags[name] ?? true; // неизвестный флаг — включён
}

abstract final class Flags {
  static const chats = 'chats', rating = 'rating', feed = 'feed';
}

enum UpdateStatus { upToDate, available, required }

/// Сравнение версий «2.1.0» без сторонних пакетов.
int compareVersions(String a, String b) {
  List<int> p(String v) => v.split('+').first.split('.').map((x) => int.tryParse(x) ?? 0).toList();
  final x = p(a), y = p(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

UpdateStatus updateStatus(String current, AppConfig c) {
  if (compareVersions(current, c.minVersion) < 0) return UpdateStatus.required;
  if (compareVersions(current, c.latestVersion) < 0) return UpdateStatus.available;
  return UpdateStatus.upToDate;
}

/// Демо-управление конфигурацией (Настройки → Для разработчика).
class ConfigController extends Notifier<AppConfig> {
  @override
  AppConfig build() => const AppConfig();
  void set(AppConfig c) => state = c;
  void setFlag(String name, bool v) =>
      state = AppConfig(minVersion: state.minVersion, latestVersion: state.latestVersion, flags: {...state.flags, name: v}, storeUrl: state.storeUrl);
}

final appConfigProvider = NotifierProvider<ConfigController, AppConfig>(ConfigController.new);

final appVersionProvider = FutureProvider<String>((ref) async => (await PackageInfo.fromPlatform()).version);

final updateStatusProvider = Provider<UpdateStatus>((ref) {
  final v = ref.watch(appVersionProvider).valueOrNull;
  if (v == null) return UpdateStatus.upToDate;
  return updateStatus(v, ref.watch(appConfigProvider));
});

final softUpdateDismissedProvider = StateProvider<bool>((ref) => false);

final flagProvider = Provider.family<bool, String>((ref, name) => ref.watch(appConfigProvider).flag(name));
