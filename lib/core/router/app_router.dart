import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/auth/screens/identifier_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/profile_setup_screen.dart';
import '../../features/auth/screens/recovery_screen.dart';
import '../../features/auth/screens/two_factor_screen.dart';
import '../../features/auth/screens/welcome_screen.dart';
import '../../features/chats/chat_screen.dart';
import '../../features/chats/chats_screen.dart';
import '../../features/design_system/design_system_screen.dart';
import '../../features/guide/guide_screen.dart';
import '../../features/setup/location_setup_screen.dart';
import '../../features/shift/roster_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/map/map_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/org/org_controller.dart';
import '../../features/org/screens/org_pending_screen.dart';
import '../../features/org/screens/org_picker_screen.dart';
import '../../features/people/people_search_screen.dart';
import '../../features/people/person_screen.dart';
import '../../features/people/rating_screen.dart';
import '../../features/profile/portfolio_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/update/update_screen.dart';
import '../../features/verify/verify_screen.dart';
import '../../features/quests/quest_detail_screen.dart';
import '../../features/shell/home_shell.dart';
import '../../features/splash/splash_gate.dart';

/// Маршруты. Каждая вкладка хранит свой стек (StatefulShellRoute).
/// Deep links (квест, приглашение, профиль друга, проверка портфолио) добавятся на этапах 5, 8, 11.
abstract final class Routes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const auth = '/auth';
  static const authIdentifier = '/auth/identifier';
  static const authOtp = '/auth/otp';
  static const auth2fa = '/auth/2fa';
  static const authProfile = '/auth/profile';
  static const authRecovery = '/auth/recovery';
  static const locationSetup = '/setup/location';
  static const guide = '/guide';
  static const org = '/org';
  static const orgPending = '/org/pending';
  static const home = '/home';
  static const map = '/map';
  static const chats = '/chats';
  static const profile = '/profile';
  static const designSystem = '/profile/design-system';
  static const portfolio = '/profile/portfolio';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Перестраиваем маршрут при входе/выходе.
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, __) => refresh.value++);
  ref.listen(membershipProvider, (_, __) => refresh.value++);
  ref.listen(updateStatusProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: Routes.splash,
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      // Принудительное обновление важнее всего остального.
      final mustUpdate = ref.read(updateStatusProvider) == UpdateStatus.required;
      if (mustUpdate) return loc == '/update' ? null : '/update';
      if (loc == '/update') return Routes.home;
      final user = ref.read(sessionProvider);
      // Проверка портфолио открывается и без входа (её присылают школе/вузу).
      final public = loc == Routes.splash || loc == Routes.onboarding || loc.startsWith(Routes.auth) || loc.startsWith('/v/');
      if (user == null && !public) return Routes.auth; // защищённые вкладки — только после входа
      if (user != null && user.needsProfile && loc != Routes.authProfile && loc != Routes.splash) return Routes.authProfile;
      if (user != null && !user.needsProfile && loc.startsWith(Routes.auth)) return Routes.home;
      // Организация не обязательна: без неё доступны все вкладки, на главной — мягкое предложение
      // после инструкции. Выбор организации открывается поверх (push), с кнопкой «Назад».
      return null;
    },
    routes: [
      GoRoute(path: Routes.splash, builder: (_, __) => const SplashGate()),
      GoRoute(path: Routes.onboarding, builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/quest/:id', builder: (_, s) => QuestDetailScreen(id: s.pathParameters['id']!), routes: [
        // Экран старшего: отметки и закрытие смены.
        GoRoute(path: 'team', builder: (_, s) => RosterScreen(questId: s.pathParameters['id']!)),
      ]),
      // Ссылка-приглашение tazaniyet.kz/q/<id> → карточка квеста (App/Universal Links — этап 11).
      GoRoute(path: '/q/:id', redirect: (_, s) => '/quest/${s.pathParameters['id']}'),
      // Переписка поверх вкладок (без нижней панели).
      GoRoute(path: '/chat/:id', builder: (_, s) => ChatScreen(chatId: s.pathParameters['id']!)),
      // Поиск волонтёров, их профили и полный рейтинг.
      GoRoute(path: '/people', builder: (_, __) => const PeopleSearchScreen(), routes: [
        GoRoute(path: ':id', builder: (_, s) => PersonScreen(id: s.pathParameters['id']!)),
      ]),
      GoRoute(path: '/rating', builder: (_, __) => const RatingScreen()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(path: '/update', builder: (_, __) => const UpdateScreen()),
      // Ссылки tazaniyet.kz/... (App Links / Universal Links): /q/<квест>, /v/<портфолио>, /u/<волонтёр>, /join/<код>.
      GoRoute(path: '/v/:code', builder: (_, s) => VerifyScreen(code: s.pathParameters['code']!)),
      GoRoute(path: '/u/:id', redirect: (_, s) => '/people/${s.pathParameters['id']}'),
      GoRoute(path: '/join/:code', builder: (_, s) => OrgPickerScreen(inviteCode: s.pathParameters['code'])),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen(), routes: [
        GoRoute(path: ':section', builder: (_, s) => SettingsSectionScreen(section: SettingsSection.values.byName(s.pathParameters['section']!))),
      ]),
      GoRoute(path: Routes.locationSetup, builder: (_, __) => const LocationSetupScreen()),
      GoRoute(path: Routes.guide, builder: (_, __) => const GuideScreen()),
      GoRoute(path: Routes.org, builder: (_, __) => const OrgPickerScreen(), routes: [
        GoRoute(path: 'pending', builder: (_, __) => const OrgPendingScreen()),
      ]),
      GoRoute(path: Routes.auth, builder: (_, __) => const WelcomeScreen(), routes: [
        GoRoute(path: 'identifier', builder: (_, __) => const IdentifierScreen()),
        GoRoute(path: 'otp', builder: (_, __) => const OtpScreen()),
        GoRoute(path: '2fa', builder: (_, __) => const TwoFactorScreen()),
        GoRoute(path: 'profile', builder: (_, __) => const ProfileSetupScreen()),
        GoRoute(path: 'recovery', builder: (_, __) => const RecoveryScreen()),
      ]),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (_, __) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.map, builder: (_, __) => const MapScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.chats, builder: (_, __) => const ChatsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.profile,
              builder: (_, __) => const ProfileScreen(),
              routes: [
                GoRoute(path: 'design-system', builder: (_, __) => const DesignSystemScreen()),
                GoRoute(path: 'portfolio', builder: (_, __) => const PortfolioScreen()),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});
