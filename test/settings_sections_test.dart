import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taza_niyet/core/settings/settings_controller.dart';
import 'package:taza_niyet/features/settings/settings_prefs.dart';

void main() {
  late ProviderContainer c;
  late SharedPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
  });
  tearDown(() => c.dispose());

  test('по умолчанию: важные уведомления включены, новости — нет', () {
    expect(c.read(toggleProvider(Toggles.nShifts)), isTrue);
    expect(c.read(toggleProvider(Toggles.nNews)), isFalse);
    expect(c.read(toggleProvider(Toggles.haptics)), isTrue);
  });

  test('переключатель сохраняется', () async {
    await c.read(toggleProvider(Toggles.reduceMotion).notifier).set(true);
    expect(prefs.getBool('toggle.${Toggles.reduceMotion}'), isTrue);
    expect(c.read(toggleProvider(Toggles.reduceMotion)), isTrue);
  });

  test('размер текста: от 100 до 150 %, шаг 10 %', () async {
    await c.read(textScaleProvider.notifier).set(2);
    expect(c.read(textScaleProvider), 1.5);
    await c.read(textScaleProvider.notifier).set(1.23);
    expect(c.read(textScaleProvider), 1.2);
  });

  test('сеансы: завершить другие — остаётся текущий', () async {
    await c.read(sessionsProvider.notifier).endOthers();
    expect(c.read(sessionsProvider).single.current, isTrue);
  });
}
