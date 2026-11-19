import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/backend/backend.dart';
import 'core/backend/backend_sync.dart';
import 'core/backend/supabase_auth.dart';
import 'core/router/app_router.dart';
import 'core/settings/settings_controller.dart';
import 'core/theme/app_theme.dart';
import 'core/ui/haptics.dart';
import 'features/settings/settings_prefs.dart';
import 'l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  // Сервер (если задан при сборке): подключиться и восстановить сеанс до первого кадра.
  await Backend.init();
  if (Backend.enabled) await supabaseAuth.restore();
  runApp(ProviderScope(
    overrides: [prefsProvider.overrideWithValue(prefs)],
    child: const TazaNiyetApp(),
  ));
}

class TazaNiyetApp extends ConsumerWidget {
  const TazaNiyetApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    ref.watch(backendSessionProvider); // синхронизация с сервером при входе
    final scale = ref.watch(textScaleProvider);
    final reduceMotion = ref.watch(toggleProvider(Toggles.reduceMotion));
    Haptics.enabled = ref.watch(toggleProvider(Toggles.haptics));
    return MaterialApp.router(
      // Название не переводится ни на один язык.
      title: 'Taza Niyet',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: settings.themeMode,
      themeAnimationDuration: const Duration(milliseconds: 200),
      locale: settings.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Язык системы не kk/ru/en → русский.
      localeResolutionCallback: (device, supported) {
        for (final l in supported) {
          if (l.languageCode == device?.languageCode) return l;
        }
        return const Locale('ru');
      },
      routerConfig: router,
      // Доступность: свой размер текста поверх системного и «меньше анимации».
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: scale == 1.0 ? mq.textScaler : TextScaler.linear(mq.textScaler.scale(1) * scale),
            disableAnimations: mq.disableAnimations || reduceMotion,
          ),
          child: child!,
        );
      },
    );
  }
}
