import 'package:flutter_test/flutter_test.dart';
import 'package:taza_niyet/features/profile/data/portfolio.dart';
import 'package:taza_niyet/features/shift/shift_controller.dart';

void main() {
  Credit shift(double h) => Credit(questTitle: 'Q', date: DateTime(2026, 11, 19), hours: h, tz: (h * 5).round(), kind: CreditKind.shift);

  test('достижения по подтверждённым сменам и часам', () {
    final a = {for (final x in achievementsFor([shift(6), shift(3), shift(2)])) x.id: x};
    expect(a[AchievementId.first]!.earned, isTrue);
    expect(a[AchievementId.shifts3]!.earned, isTrue);
    expect(a[AchievementId.h10]!.earned, isTrue); // 11 ч
    expect(a[AchievementId.shifts5]!.progress, closeTo(.6, .001));
    expect(a[AchievementId.senior]!.earned, isFalse);
  });

  test('бонус старшего открывает «Старший»', () {
    final a = achievementsFor([Credit(questTitle: 'Q', date: DateTime(2026), hours: 0, tz: 10, kind: CreditKind.seniorBonus)]);
    expect(a.firstWhere((x) => x.id == AchievementId.senior).earned, isTrue);
    expect(a.firstWhere((x) => x.id == AchievementId.first).earned, isFalse); // бонус — не смена
  });

  test('номер портфолио стабильный, 8 символов, без 0/O/1/I', () {
    final c = portfolioCode('user-42');
    expect(c, portfolioCode('user-42'));
    expect(c, hasLength(8));
    expect(c.startsWith('TN'), isTrue);
    expect(RegExp(r'[01OI]').hasMatch(c.substring(2)), isFalse);
    expect(portfolioCode('user-43'), isNot(c));
  });

  test('до 18 лет «Все» превращается в «Друзья»', () {
    expect(effectiveVisibility(HoursVisibility.everyone, minor: true), HoursVisibility.friends);
    expect(effectiveVisibility(HoursVisibility.everyone, minor: false), HoursVisibility.everyone);
    expect(effectiveVisibility(HoursVisibility.onlyMe, minor: true), HoursVisibility.onlyMe);
  });
}
