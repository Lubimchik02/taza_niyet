import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Демо-переключатель «нет сети» (Настройки → Для разработчика).
final devOfflineProvider = StateProvider<bool>((ref) => false);

final _systemOnlineProvider = StreamProvider<bool>((ref) async* {
  final c = Connectivity();
  bool online(List<ConnectivityResult> r) => r.any((x) => x != ConnectivityResult.none);
  yield online(await c.checkConnectivity());
  yield* c.onConnectivityChanged.map(online);
});

/// Есть ли сеть. Пока неизвестно — считаем, что есть (не пугаем баннером при запуске).
final isOnlineProvider = Provider<bool>((ref) {
  if (ref.watch(devOfflineProvider)) return false;
  return ref.watch(_systemOnlineProvider).valueOrNull ?? true;
});
