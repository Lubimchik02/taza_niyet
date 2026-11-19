import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' hide AuthUser;

import '../../features/auth/data/auth_repository.dart';
import 'backend.dart';

/// Вход через Supabase Auth: код на почту или по СМС, Apple/Google, вторая ступень (TOTP).
/// Профиль (имя, год рождения, согласие) — таблица profiles.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository();

  SupabaseClient get _db => Backend.client;
  AuthUser? _user;

  /// Восстановить сеанс и профиль при запуске (до первого кадра).
  Future<void> restore() async {
    final u = _db.auth.currentUser;
    _user = u == null ? null : await _load(u);
  }

  Future<AuthUser> _load(User u) async {
    final p = await _db.from('profiles').select('name, birth_year').eq('id', u.id).maybeSingle();
    final factors = await _db.auth.mfa.listFactors();
    return AuthUser(
      id: u.id,
      name: p?['name'] as String?,
      birthYear: p?['birth_year'] as int?,
      email: u.email,
      phone: u.phone,
      hasTwoFactor: factors.totp.any((f) => f.status == FactorStatus.verified),
    );
  }

  AuthFailure _map(Object e) {
    if (e is SocketException || e is TimeoutException) return const AuthFailure(AuthFailureKind.network);
    if (e is AuthException) {
      if (e.statusCode == '429' || (e.code ?? '').contains('rate_limit')) return const AuthFailure(AuthFailureKind.rateLimited);
      // Supabase отвечает одинаково на неверный и просроченный код.
      if ((e.code ?? '') == 'otp_expired' || e.message.toLowerCase().contains('expired')) return const AuthFailure(AuthFailureKind.wrongCode);
    }
    return const AuthFailure(AuthFailureKind.unknown);
  }

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<OtpChallenge> sendCode(AuthChannel channel, String target) async {
    try {
      if (channel == AuthChannel.email) {
        await _db.auth.signInWithOtp(email: target, shouldCreateUser: true);
      } else {
        await _db.auth.signInWithOtp(phone: target, shouldCreateUser: true);
      }
      return OtpChallenge(channel: channel, target: target, resendAt: DateTime.now().add(const Duration(seconds: 60)), attemptsLeft: 5);
    } catch (e) {
      throw _map(e);
    }
  }

  Future<SignInResult> _afterSignIn() async {
    final u = await _load(_db.auth.currentUser!);
    final aal = _db.auth.mfa.getAuthenticatorAssuranceLevel();
    if (aal.nextLevel == AuthenticatorAssuranceLevels.aal2 && aal.currentLevel != AuthenticatorAssuranceLevels.aal2) {
      return NeedsSecondFactor(u);
    }
    _user = u;
    return SignedIn(u);
  }

  @override
  Future<SignInResult> verifyCode(OtpChallenge challenge, String code) async {
    try {
      if (challenge.channel == AuthChannel.email) {
        await _db.auth.verifyOTP(type: OtpType.email, email: challenge.target, token: code);
      } else {
        await _db.auth.verifyOTP(type: OtpType.sms, phone: challenge.target, token: code);
      }
      return _afterSignIn();
    } catch (e) {
      final f = _map(e);
      if (f.kind == AuthFailureKind.wrongCode) {
        final left = challenge.attemptsLeft - 1;
        throw left <= 0 ? const AuthFailure(AuthFailureKind.tooManyAttempts) : AuthFailure(AuthFailureKind.wrongCode, attemptsLeft: left);
      }
      throw f;
    }
  }

  @override
  Future<AuthUser> verifySecondFactor(AuthUser pending, String code, {bool backup = false}) async {
    // Резервных кодов в Supabase нет: восстановление второй ступени — через поддержку.
    if (backup) throw const AuthFailure(AuthFailureKind.unknown);
    try {
      final factor = (await _db.auth.mfa.listFactors()).totp.firstWhere((f) => f.status == FactorStatus.verified);
      await _db.auth.mfa.challengeAndVerify(factorId: factor.id, code: code);
      return _user = await _load(_db.auth.currentUser!);
    } catch (e) {
      throw e is AuthFailure ? e : const AuthFailure(AuthFailureKind.wrongCode);
    }
  }

  Future<SignInResult> _oauth(OAuthProvider p) async {
    try {
      final done = _db.auth.onAuthStateChange.firstWhere((s) => s.event == AuthChangeEvent.signedIn).timeout(const Duration(minutes: 5));
      final opened = await _db.auth.signInWithOAuth(p, redirectTo: Backend.authRedirect);
      if (!opened) throw const AuthFailure(AuthFailureKind.cancelled);
      await done;
      return _afterSignIn();
    } on TimeoutException {
      throw const AuthFailure(AuthFailureKind.cancelled);
    } catch (e) {
      throw e is AuthFailure ? e : _map(e);
    }
  }

  @override
  Future<SignInResult> signInWithApple() => _oauth(OAuthProvider.apple);

  @override
  Future<SignInResult> signInWithGoogle() => _oauth(OAuthProvider.google);

  /// Ключи доступа (WebAuthn) Supabase Auth пока не поддерживает — кнопка скрыта (флаг passkeys).
  @override
  Future<SignInResult> signInWithPasskey() async => throw const AuthFailure(AuthFailureKind.unknown);

  @override
  Future<AuthUser> completeProfile(AuthUser user, {required String name, required int birthYear}) async {
    try {
      // consent_at / consent_version — момент согласия на обработку персональных данных (экран профиля).
      await _db.from('profiles').upsert({'id': user.id, 'name': name, 'birth_year': birthYear, 'consent_version': '2026-11'});
      return _user = user.copyWith(name: name, birthYear: birthYear);
    } catch (e) {
      throw _map(e);
    }
  }

  @override
  Future<AuthUser> updateName(AuthUser user, String name) async {
    await _db.from('profiles').update({'name': name}).eq('id', user.id);
    return _user = user.copyWith(name: name);
  }

  @override
  Future<void> requestDeletion() async {
    await _db.rpc('request_account_deletion');
    await signOut();
  }

  @override
  Future<void> signOut() async {
    await _db.auth.signOut();
    _user = null;
  }
}

/// Один экземпляр: сеанс восстанавливается в main() до первого кадра.
final supabaseAuth = SupabaseAuthRepository();
