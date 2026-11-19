import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Пользователь после входа.
@immutable
class AuthUser {
  const AuthUser({required this.id, this.name, this.birthYear, this.email, this.phone, this.hasTwoFactor = false});

  final String id;
  final String? name;
  final int? birthYear;
  final String? email;
  final String? phone;
  final bool hasTwoFactor;

  /// Новый пользователь ещё не заполнил имя и год рождения.
  bool get needsProfile => name == null || birthYear == null;

  AuthUser copyWith({String? name, int? birthYear}) => AuthUser(
        id: id,
        name: name ?? this.name,
        birthYear: birthYear ?? this.birthYear,
        email: email,
        phone: phone,
        hasTwoFactor: hasTwoFactor,
      );

  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'birthYear': birthYear, 'email': email, 'phone': phone, 'twoFa': hasTwoFactor};

  static AuthUser fromJson(Map<String, Object?> j) => AuthUser(
        id: j['id']! as String,
        name: j['name'] as String?,
        birthYear: j['birthYear'] as int?,
        email: j['email'] as String?,
        phone: j['phone'] as String?,
        hasTwoFactor: j['twoFa'] as bool? ?? false,
      );
}

enum AuthChannel { email, phone }

/// Отправленный код: куда, сколько попыток осталось, когда можно повторить.
@immutable
class OtpChallenge {
  const OtpChallenge({required this.channel, required this.target, required this.resendAt, required this.attemptsLeft});

  final AuthChannel channel;
  final String target;
  final DateTime resendAt;
  final int attemptsLeft;

  OtpChallenge copyWith({DateTime? resendAt, int? attemptsLeft}) => OtpChallenge(
        channel: channel,
        target: target,
        resendAt: resendAt ?? this.resendAt,
        attemptsLeft: attemptsLeft ?? this.attemptsLeft,
      );
}

enum AuthFailureKind { network, rateLimited, wrongCode, codeExpired, tooManyAttempts, cancelled, unknown }

class AuthFailure implements Exception {
  const AuthFailure(this.kind, {this.attemptsLeft});

  final AuthFailureKind kind;
  final int? attemptsLeft;
}

/// Результат проверки кода: либо вошли, либо нужен второй фактор.
sealed class SignInResult {
  const SignInResult();
}

class SignedIn extends SignInResult {
  const SignedIn(this.user);
  final AuthUser user;
}

class NeedsSecondFactor extends SignInResult {
  const NeedsSecondFactor(this.pendingUser);
  final AuthUser pendingUser;
}

/// Контракт входа. Реальная реализация (Supabase Auth + Apple + Google + passkeys,
/// токены в Keychain/Keystore) — этап 12. Сейчас — [FakeAuthRepository].
abstract interface class AuthRepository {
  AuthUser? get currentUser;
  Future<OtpChallenge> sendCode(AuthChannel channel, String target);
  Future<SignInResult> verifyCode(OtpChallenge challenge, String code);
  Future<AuthUser> verifySecondFactor(AuthUser pending, String code, {bool backup = false});
  Future<SignInResult> signInWithApple();
  Future<SignInResult> signInWithGoogle();
  Future<SignInResult> signInWithPasskey();
  Future<AuthUser> completeProfile(AuthUser user, {required String name, required int birthYear});
  Future<void> signOut();

  /// Новое имя (год рождения — только через поддержку).
  Future<AuthUser> updateName(AuthUser user, String name);

  /// Запрос на удаление: 30 дней на отмену (вход снова), потом — безвозвратно (требование App Store / Google Play).
  Future<void> requestDeletion();
}

/// Демо-реализация для прототипа и тестов. Правила:
/// • номер +77000000000 → ошибка сети; • код 000000 → неверный; • код 111111 → устарел;
/// • email, начинающийся с «2fa», → включена двухфакторная защита; • любой другой код — вход.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository(this._prefs, {this.delay = const Duration(milliseconds: 700)}) {
    final raw = _prefs.getString(_kUser);
    if (raw != null) _user = AuthUser.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  final SharedPreferences _prefs;
  final Duration delay;
  static const _kUser = 'demo.auth.user';
  static const _resendAfter = Duration(seconds: 60);
  AuthUser? _user;
  final _known = <String, AuthUser>{};

  @override
  AuthUser? get currentUser => _user;

  Future<void> _save(AuthUser? u) async {
    _user = u;
    if (u == null) {
      await _prefs.remove(_kUser);
    } else {
      await _prefs.setString(_kUser, jsonEncode(u.toJson()));
    }
  }

  @override
  Future<OtpChallenge> sendCode(AuthChannel channel, String target) async {
    await Future<void>.delayed(delay);
    if (target == '+77000000000') throw const AuthFailure(AuthFailureKind.network);
    return OtpChallenge(channel: channel, target: target, resendAt: DateTime.now().add(_resendAfter), attemptsLeft: 5);
  }

  @override
  Future<SignInResult> verifyCode(OtpChallenge c, String code) async {
    await Future<void>.delayed(delay);
    if (c.attemptsLeft <= 0) throw const AuthFailure(AuthFailureKind.tooManyAttempts);
    if (code == '111111') throw const AuthFailure(AuthFailureKind.codeExpired);
    if (code == '000000') {
      final left = c.attemptsLeft - 1;
      throw AuthFailure(left <= 0 ? AuthFailureKind.tooManyAttempts : AuthFailureKind.wrongCode, attemptsLeft: left);
    }
    final user = _known[c.target] ??
        AuthUser(
          id: 'u_${c.target.hashCode.abs()}',
          email: c.channel == AuthChannel.email ? c.target : null,
          phone: c.channel == AuthChannel.phone ? c.target : null,
          hasTwoFactor: c.target.startsWith('2fa'),
        );
    _known[c.target] = user;
    if (user.hasTwoFactor) return NeedsSecondFactor(user);
    await _save(user);
    return SignedIn(user);
  }

  @override
  Future<AuthUser> verifySecondFactor(AuthUser pending, String code, {bool backup = false}) async {
    await Future<void>.delayed(delay);
    if (code == '000000' || code.isEmpty) throw const AuthFailure(AuthFailureKind.wrongCode, attemptsLeft: 4);
    await _save(pending);
    return pending;
  }

  Future<SignInResult> _social(String provider) async {
    await Future<void>.delayed(delay);
    final user = _known[provider] ?? AuthUser(id: 'u_$provider');
    _known[provider] = user;
    await _save(user);
    return SignedIn(user);
  }

  @override
  Future<SignInResult> signInWithApple() => _social('apple');

  @override
  Future<SignInResult> signInWithGoogle() => _social('google');

  @override
  Future<SignInResult> signInWithPasskey() => _social('passkey');

  @override
  Future<AuthUser> completeProfile(AuthUser user, {required String name, required int birthYear}) async {
    await Future<void>.delayed(delay);
    final u = user.copyWith(name: name.trim(), birthYear: birthYear);
    await _save(u);
    return u;
  }

  @override
  Future<void> signOut() => _save(null);

  @override
  Future<AuthUser> updateName(AuthUser user, String name) async {
    await Future<void>.delayed(delay);
    final u = user.copyWith(name: name);
    await _save(u);
    return u;
  }

  @override
  Future<void> requestDeletion() async {
    await Future<void>.delayed(delay);
    await _save(null);
  }
}
