import 'package:flutter/services.dart';

/// Тактильный отклик на ключевых действиях.
enum HapticKind { none, light, medium, success }

abstract final class Haptics {
  /// Выключается в Настройки → Доступность.
  static bool enabled = true;

  static void play(HapticKind kind) {
    if (!enabled) return;
    switch (kind) {
      case HapticKind.none:
        return;
      case HapticKind.light: // выбор чипа, вкладки
        HapticFeedback.selectionClick();
      case HapticKind.medium: // запись, «Я на месте», отправка
        HapticFeedback.mediumImpact();
      case HapticKind.success: // подтверждение часов
        HapticFeedback.heavyImpact();
    }
  }
}
