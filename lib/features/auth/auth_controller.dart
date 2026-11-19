import '../../core/backend/backend.dart';
import '../../core/backend/supabase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_x.dart';
import '../../core/settings/settings_controller.dart';
import 'data/auth_repository.dart';

/// Репозиторий входа. На этапе 12 заменяется на реальный (Supabase).
// Сервер, если при сборке заданы SUPABASE_URL и SUPABASE_ANON_KEY; иначе демо.
final authRepositoryProvider = Provider<AuthRepository>((ref) => Backend.enabled ? supabaseAuth : FakeAuthRepository(ref.watch(prefsProvider)));

/// Текущий пользователь (null — не вошёл).
class SessionController extends Notifier<AuthUser?> {
  @override
  AuthUser? build() => ref.read(authRepositoryProvider).currentUser;

  void set(AuthUser? user) => state = user;

  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = null;
  }

  Future<void> rename(String name) async {
    if (state == null) return;
    state = await ref.read(authRepositoryProvider).updateName(state!, name);
  }

  Future<void> deleteAccount() async {
    await ref.read(authRepositoryProvider).requestDeletion();
    state = null;
  }
}

final sessionProvider = NotifierProvider<SessionController, AuthUser?>(SessionController.new);

/// Шаг входа между экранами: отправленный код и пользователь, ждущий второй фактор.
class AuthFlowState {
  const AuthFlowState({this.challenge, this.pendingUser});
  final OtpChallenge? challenge;
  final AuthUser? pendingUser;
}

class AuthFlowController extends Notifier<AuthFlowState> {
  @override
  AuthFlowState build() => const AuthFlowState();

  void setChallenge(OtpChallenge? c) => state = AuthFlowState(challenge: c, pendingUser: state.pendingUser);
  void setPending(AuthUser? u) => state = AuthFlowState(challenge: state.challenge, pendingUser: u);
  void reset() => state = const AuthFlowState();
}

final authFlowProvider = NotifierProvider<AuthFlowController, AuthFlowState>(AuthFlowController.new);

/// Понятный текст ошибки на языке пользователя.
String authErrorText(BuildContext context, Object e) {
  final l = context.l;
  if (e is! AuthFailure) return l.errUnknown;
  return switch (e.kind) {
    AuthFailureKind.network => l.errorNetworkBody,
    AuthFailureKind.rateLimited => l.errRate,
    AuthFailureKind.wrongCode => l.errWrongCode(e.attemptsLeft ?? 0),
    AuthFailureKind.codeExpired => l.errCodeExpired,
    AuthFailureKind.tooManyAttempts => l.errTooMany,
    AuthFailureKind.cancelled => l.errCancelled,
    AuthFailureKind.unknown => l.errUnknown,
  };
}
