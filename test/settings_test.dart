import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taza_niyet/core/settings/settings_controller.dart';

void main() {
  test('инструкция и вопрос о местоположении запоминаются и сбрасываются', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(prefs)]);
    addTearDown(c.dispose);

    expect(c.read(settingsProvider).guideSeen, isFalse);
    expect(c.read(settingsProvider).locationAsked, isFalse);

    await c.read(settingsProvider.notifier).markLocationAsked();
    await c.read(settingsProvider.notifier).markGuideSeen();
    expect(prefs.getBool('settings.guideSeen'), isTrue);
    expect(c.read(settingsProvider).locationAsked, isTrue);

    await c.read(settingsProvider.notifier).resetOnboarding();
    expect(c.read(settingsProvider).guideSeen, isFalse);
    expect(c.read(settingsProvider).locationAsked, isFalse);
  });
}
