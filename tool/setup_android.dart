// Подготовка папки android/ после `flutter create` — один раз.
// Запуск из корня проекта:  dart run tool/setup_android.dart
//
// Что делает:
//  • minSdk 24 (нужно для Firebase и уведомлений), applicationId kz.tazaniyet.app;
//  • включает desugaring (без него flutter_local_notifications не собирается);
//  • добавляет разрешения: интернет, геолокация, уведомления;
//  • название приложения «Taza Niyet»;
//  • проверяет, что шрифты Manrope лежат в assets/fonts.
// Повторный запуск безопасен: уже сделанные правки не дублируются.
import 'dart:io';

void main() {
  final kts = File('android/app/build.gradle.kts');
  final groovy = File('android/app/build.gradle');
  final manifest = File('android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync() || (!kts.existsSync() && !groovy.existsSync())) {
    _fail('Нет папки android/. Сначала выполните:\n'
        '  flutter create --org kz.tazaniyet --project-name taza_niyet --platforms android .');
  }

  if (kts.existsSync()) {
    kts.writeAsStringSync(patchKts(kts.readAsStringSync()));
    print('✓ android/app/build.gradle.kts');
  } else {
    groovy.writeAsStringSync(patchGroovy(groovy.readAsStringSync()));
    print('✓ android/app/build.gradle');
  }
  manifest.writeAsStringSync(patchManifest(manifest.readAsStringSync()));
  print('✓ AndroidManifest.xml');

  const fonts = ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold'];
  final missing = [for (final w in fonts) if (!File('assets/fonts/Manrope-$w.ttf').existsSync()) 'Manrope-$w.ttf'];
  if (missing.isEmpty) {
    print('✓ шрифты Manrope на месте');
  } else {
    print('\n! Не хватает шрифтов в assets/fonts: ${missing.join(', ')}');
    print('  Скачайте Manrope: https://fonts.google.com/specimen/Manrope → «Get font» → «Download all»,');
    print('  распакуйте и скопируйте файлы из папки static/ в assets/fonts/.');
    exitCode = 1;
    return;
  }
  print('\nГотово. Дальше: flutter run');
}

String patchKts(String s) {
  s = s.replaceAll(RegExp(r'minSdk\s*=\s*[^\n]+'), 'minSdk = 24');
  s = s.replaceAll(RegExp(r'applicationId\s*=\s*"[^"]*"'), 'applicationId = "kz.tazaniyet.app"');
  if (!s.contains('isCoreLibraryDesugaringEnabled')) {
    s = s.replaceFirst(RegExp(r'compileOptions\s*\{'), 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true');
  }
  if (!s.contains('desugar_jdk_libs')) {
    s = '${s.trimRight()}\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n';
  }
  return s;
}

String patchGroovy(String s) {
  s = s.replaceAll(RegExp(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion'), 'minSdk = 24');
  s = s.replaceAll(RegExp(r'applicationId\s*=?\s*"[^"]*"'), 'applicationId = "kz.tazaniyet.app"');
  if (!s.contains('coreLibraryDesugaringEnabled')) {
    s = s.replaceFirst(RegExp(r'compileOptions\s*\{'), 'compileOptions {\n        coreLibraryDesugaringEnabled true');
  }
  if (!s.contains('desugar_jdk_libs')) {
    s = "${s.trimRight()}\n\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n";
  }
  return s;
}

String patchManifest(String s) {
  const perms = [
    'android.permission.INTERNET',
    'android.permission.ACCESS_FINE_LOCATION',
    'android.permission.ACCESS_COARSE_LOCATION',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.RECEIVE_BOOT_COMPLETED',
  ];
  final add = [for (final p in perms) if (!s.contains('"$p"')) '    <uses-permission android:name="$p" />'];
  if (add.isNotEmpty) {
    final m = RegExp(r'<manifest[^>]*>').firstMatch(s)!;
    s = '${s.substring(0, m.end)}\n${add.join('\n')}${s.substring(m.end)}';
  }
  return s.replaceFirst(RegExp(r'android:label="[^"]*"'), 'android:label="Taza Niyet"');
}

Never _fail(String msg) {
  stderr.writeln(msg);
  exit(1);
}
