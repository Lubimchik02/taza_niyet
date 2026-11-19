import 'package:flutter/foundation.dart';

import '../../shift/shift_controller.dart';

enum AchievementId { first, shifts3, shifts5, h10, h50, senior }

@immutable
class Achievement {
  const Achievement(this.id, {required this.current, required this.target});
  final AchievementId id;
  final double current, target;

  bool get earned => current >= target;
  double get progress => (current / target).clamp(0, 1);
}

/// Достижения считаются только по подтверждённым координатором начислениям.
List<Achievement> achievementsFor(List<Credit> credits) {
  final shifts = credits.where((c) => c.kind == CreditKind.shift).length.toDouble();
  final hours = credits.fold(0.0, (a, c) => a + c.hours);
  final senior = credits.any((c) => c.kind == CreditKind.seniorBonus) ? 1.0 : 0.0;
  return [
    Achievement(AchievementId.first, current: shifts, target: 1),
    Achievement(AchievementId.shifts3, current: shifts, target: 3),
    Achievement(AchievementId.h10, current: hours, target: 10),
    Achievement(AchievementId.shifts5, current: shifts, target: 5),
    Achievement(AchievementId.h50, current: hours, target: 50),
    Achievement(AchievementId.senior, current: senior, target: 1),
  ];
}

/// Номер портфолио для проверки: стабильный, без личных данных, легко продиктовать
/// (без похожих символов 0/O, 1/I). На сервере — случайный токен с отзывом (этап 12).
String portfolioCode(String userId) {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  var h = 0x811c9dc5;
  for (final c in userId.codeUnits) {
    h = ((h ^ c) * 0x01000193) & 0xffffffff;
  }
  final b = StringBuffer('TN');
  for (var i = 0; i < 6; i++) {
    b.write(alphabet[h % alphabet.length]);
    h = (h ~/ alphabet.length) ^ (h << 5 & 0xffffffff);
  }
  return b.toString();
}

String portfolioLink(String code) => 'https://tazaniyet.kz/v/$code';

/// Кто видит итог часов в профиле. До 18 лет — максимум «друзья».
enum HoursVisibility { everyone, friends, onlyMe }

HoursVisibility effectiveVisibility(HoursVisibility chosen, {required bool minor}) =>
    minor && chosen == HoursVisibility.everyone ? HoursVisibility.friends : chosen;
