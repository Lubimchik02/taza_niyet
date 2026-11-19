import '../backend/backend.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Предоставляется в main() через override.
final prefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('prefsProvider не переопределён'));

@immutable
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.locale,
    this.onboardingSeen = false,
    this.guideSeen = false,
    this.locationAsked = false,
  });

  final ThemeMode themeMode;

  /// null — язык системы (если он kk/ru/en), иначе русский.
  final Locale? locale;

  /// Онбординг уже показан: полная заставка и слайды — только при первом запуске.
  final bool onboardingSeen;

  /// Инструкция «Как это работает» прочитана — после этого на главной мягко предлагаем организацию.
  final bool guideSeen;

  /// Экран про местоположение уже показан после регистрации (ответ любой).
  final bool locationAsked;

  AppSettings copyWith({ThemeMode? themeMode, Locale? Function()? locale, bool? onboardingSeen, bool? guideSeen, bool? locationAsked}) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        locale: locale != null ? locale() : this.locale,
        onboardingSeen: onboardingSeen ?? this.onboardingSeen,
        guideSeen: guideSeen ?? this.guideSeen,
        locationAsked: locationAsked ?? this.locationAsked,
      );
}

class SettingsController extends Notifier<AppSettings> {
  static const _kTheme = 'settings.theme';
  static const _kLocale = 'settings.locale';
  static const _kOnboarding = 'settings.onboardingSeen';
  static const _kGuide = 'settings.guideSeen';
  static const _kLocAsked = 'settings.locationAsked';

  SharedPreferences get _prefs => ref.read(prefsProvider);

  @override
  AppSettings build() {
    final prefs = ref.watch(prefsProvider);
    final theme = prefs.getString(_kTheme);
    final locale = prefs.getString(_kLocale);
    return AppSettings(
      themeMode: ThemeMode.values.firstWhere((m) => m.name == theme, orElse: () => ThemeMode.system),
      locale: locale == null ? null : Locale(locale),
      onboardingSeen: prefs.getBool(_kOnboarding) ?? false,
      guideSeen: prefs.getBool(_kGuide) ?? false,
      locationAsked: prefs.getBool(_kLocAsked) ?? false,
    );
  }

  Future<void> markOnboardingSeen() async {
    state = state.copyWith(onboardingSeen: true);
    await _prefs.setBool(_kOnboarding, true);
  }

  Future<void> markGuideSeen() async {
    state = state.copyWith(guideSeen: true);
    await _prefs.setBool(_kGuide, true);
  }

  Future<void> markLocationAsked() async {
    state = state.copyWith(locationAsked: true);
    await _prefs.setBool(_kLocAsked, true);
  }

  /// Для проверки в debug: снова показать заставку, онбординг, вопрос о местоположении и инструкцию.
  Future<void> resetOnboarding() async {
    state = state.copyWith(onboardingSeen: false, guideSeen: false, locationAsked: false);
    await Future.wait([_prefs.remove(_kOnboarding), _prefs.remove(_kGuide), _prefs.remove(_kLocAsked)]);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = state.copyWith(themeMode: mode);
    await _prefs.setString(_kTheme, mode.name);
  }

  Future<void> setLocale(Locale? locale) async {
    state = state.copyWith(locale: () => locale);
    // Язык пушей на сервере.
    final uid = Backend.enabled ? Backend.client.auth.currentUser?.id : null;
    if (uid != null && locale != null) {
      Backend.client.from('profiles').update({'locale': locale.languageCode}).eq('id', uid).then((_) {}, onError: (_) {});
    }
    if (locale == null) {
      await _prefs.remove(_kLocale);
    } else {
      await _prefs.setString(_kLocale, locale.languageCode);
    }
  }
}

final settingsProvider = NotifierProvider<SettingsController, AppSettings>(SettingsController.new);
