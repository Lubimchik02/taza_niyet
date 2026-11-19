# Выпуск Taza Niyet в App Store и Google Play

Полный чек-лист с текстами карточек, анкетами и бета-тестом — в документе
«Taza Niyet — публикация в App Store и Google Play». Здесь только команды.

## 0. Один раз: платформенные папки

В репозитории нет `android/` и `ios/` — их создаёт Flutter:

```bash
flutter create --org kz.tazaniyet --project-name taza_niyet --platforms android,ios .
dart run tool/setup_android.dart     # minSdk, desugaring, разрешения, название; проверит шрифты
flutter pub get
```

Шрифты: Manrope с https://fonts.google.com/specimen/Manrope («Get font» → «Download all»),
файлы `static/Manrope-{Regular,Medium,SemiBold,Bold,ExtraBold}.ttf` → `assets/fonts/`.

Затем перенести настройки из `platform/`:

| Файл из `platform/` | Куда |
| --- | --- |
| `android/build.gradle.kts.snippet` | `android/app/build.gradle.kts` (блок `android {…}` и подпись) |
| `android/AndroidManifest.additions.xml` | `android/app/src/main/AndroidManifest.xml` |
| `ios/Info.plist.additions.xml` | `ios/Runner/Info.plist` |
| `ios/{ru,kk,en}.lproj/InfoPlist.strings` | `ios/Runner/` + добавить языки в Xcode (Project → Info → Localizations) |
| `ios/Runner.entitlements` | `ios/Runner/` + Signing & Capabilities: Push, Associated Domains, Sign in with Apple |
| `ios/PrivacyInfo.xcprivacy` | `ios/Runner/` (добавить в target Runner) |

iOS: в `ios/Podfile` — `platform :ios, '15.0'`; в Xcode → Runner → General →
Supported Destinations оставить только iPhone.

Иконки: `store/icons/AppIcon-1024.png` →
`dart run flutter_launcher_icons` или вручную в `Assets.xcassets`; для Android — Image Asset в Android Studio.

Firebase (пуши): `android/app/google-services.json`, `ios/Runner/GoogleService-Info.plist`;
ключ APNs (.p8) загрузить в Firebase → Cloud Messaging.

## 1. Сервер

```bash
cd supabase
supabase link --project-ref <ref>        # или psql к своему серверу в Казахстане
supabase db push                          # миграции 0100–0800
supabase secrets set FCM_SERVICE_ACCOUNT="$(cat service-account.json)"
supabase functions deploy push
```

Тесты перед выкладкой — см. `supabase/README.md` (4 набора, все должны пройти).

Тестовый вход для проверяющих: Auth → Phone → Test phone numbers (номер + постоянный код).
Квест для проверяющих без проверки расстояния:

```sql
update quests set checkin_anywhere = true where id = '<id квеста App Review>';
```

## 2. Подпись Android

```bash
keytool -genkey -v -keystore ~/keys/tazaniyet-upload.jks -keyalg RSA -keysize 2048 \
        -validity 10000 -alias upload
```

`android/key.properties` (в `.gitignore`!):

```properties
storePassword=…
keyPassword=…
keyAlias=upload
storeFile=/Users/<вы>/keys/tazaniyet-upload.jks
```

В Play Console включить Play App Signing. Отпечаток SHA-256 **ключа подписи приложения**
(Play Console → Настройка → Целостность приложения) вписать в `web/.well-known/assetlinks.json`.

## 3. Сборка

Версия — в `pubspec.yaml`: `version: 1.0.0+1`. Число после `+` растёт на 1 с каждой загрузкой.

```bash
DEFINES="--dart-define=SUPABASE_URL=https://api.tazaniyet.kz --dart-define=SUPABASE_ANON_KEY=<anon-ключ>"

flutter test
flutter build appbundle --release $DEFINES     # → build/app/outputs/bundle/release/app-release.aab
flutter build ipa --release $DEFINES           # → build/ios/ipa/*.ipa
```

Без `--dart-define` собирается демо-версия с выдуманными данными — в магазины её не отправлять.
Anon-ключ публичный (его видно в приложении), но service_role-ключ в приложение не попадает никогда.

## 4. Загрузка

- Android: Play Console → Тестирование → Закрытое тестирование → новый выпуск → `.aab`.
- iOS: `xcrun altool` или приложение Transporter → `.ipa`; затем TestFlight.
- Скриншоты и баннер: `store/` (архив `taza_niyet_store.zip`), тексты: `store/listing/`.

## 5. Обновления

1. `version: 1.0.1+2` в `pubspec.yaml`.
2. Новые миграции — только новыми файлами, старые не менять.
3. Если обновление обязательное — поднять `min_version` в `app_config`, старые версии покажут экран «Обновите приложение».
