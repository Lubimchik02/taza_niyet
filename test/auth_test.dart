import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taza_niyet/features/auth/data/auth_repository.dart';
import 'package:taza_niyet/features/auth/data/validators.dart';

void main() {
  group('проверка ввода', () {
    test('email', () {
      expect(AuthValidators.isEmail('arman@mail.kz'), isTrue);
      expect(AuthValidators.isEmail(' arman@mail.kz '), isTrue);
      expect(AuthValidators.isEmail('arman.mail.kz'), isFalse);
      expect(AuthValidators.isEmail('arman@mail'), isFalse);
    });

    test('казахстанский номер в любом привычном виде', () {
      expect(AuthValidators.normalizeKzPhone('+7 777 123 45 67'), '+77771234567');
      expect(AuthValidators.normalizeKzPhone('8 (777) 123-45-67'), '+77771234567');
      expect(AuthValidators.normalizeKzPhone('77771234567'), '+77771234567');
      expect(AuthValidators.normalizeKzPhone('7771234567'), '+77771234567');
      expect(AuthValidators.normalizeKzPhone('+7 912 123 45 67'), isNull); // не казахстанский мобильный
      expect(AuthValidators.normalizeKzPhone('123'), isNull);
      expect(AuthValidators.formatKzPhone('+77771234567'), '+7 777 123 45 67');
    });

    test('имя — хотя бы 2 буквы, на любом языке', () {
      expect(AuthValidators.isName('Арман'), isTrue);
      expect(AuthValidators.isName('Әсем'), isTrue);
      expect(AuthValidators.isName('A'), isFalse);
      expect(AuthValidators.isName('  '), isFalse);
    });

    test('несовершеннолетний по году рождения (по худшему случаю)', () {
      final now = DateTime(2026, 11, 18);
      expect(AuthValidators.isMinor(2008, now: now), isTrue); // мог ещё не отметить 18
      expect(AuthValidators.isMinor(2007, now: now), isFalse);
    });
  });

  group('демо-вход', () {
    late FakeAuthRepository repo;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      repo = FakeAuthRepository(await SharedPreferences.getInstance(), delay: Duration.zero);
    });

    test('новый пользователь входит по коду и должен заполнить профиль', () async {
      final c = await repo.sendCode(AuthChannel.email, 'arman@mail.kz');
      expect(c.attemptsLeft, 5);
      final r = await repo.verifyCode(c, '123456');
      expect(r, isA<SignedIn>());
      expect((r as SignedIn).user.needsProfile, isTrue);
      final u = await repo.completeProfile(r.user, name: 'Арман', birthYear: 2000);
      expect(u.needsProfile, isFalse);
      expect(repo.currentUser?.name, 'Арман');
    });

    test('неверный код уменьшает попытки, на последней — блокировка', () async {
      var c = await repo.sendCode(AuthChannel.email, 'arman@mail.kz');
      for (var left = 4; left >= 1; left--) {
        final e = await repo.verifyCode(c, '000000').then<AuthFailure?>((_) => null, onError: (Object e) => e as AuthFailure);
        expect(e!.kind, AuthFailureKind.wrongCode);
        expect(e.attemptsLeft, left);
        c = c.copyWith(attemptsLeft: left);
      }
      expect(
        () => repo.verifyCode(c, '000000'),
        throwsA(isA<AuthFailure>().having((e) => e.kind, 'kind', AuthFailureKind.tooManyAttempts)),
      );
    });

    test('двухфакторная защита требует второй шаг', () async {
      final c = await repo.sendCode(AuthChannel.email, '2fa@mail.kz');
      final r = await repo.verifyCode(c, '123456');
      expect(r, isA<NeedsSecondFactor>());
      expect(repo.currentUser, isNull);
      await repo.verifySecondFactor((r as NeedsSecondFactor).pendingUser, '654321');
      expect(repo.currentUser, isNotNull);
    });

    test('ошибка сети при отправке кода', () async {
      expect(
        () => repo.sendCode(AuthChannel.phone, '+77000000000'),
        throwsA(isA<AuthFailure>().having((e) => e.kind, 'kind', AuthFailureKind.network)),
      );
    });

    test('выход очищает сессию', () async {
      await repo.signInWithApple();
      expect(repo.currentUser, isNotNull);
      await repo.signOut();
      expect(repo.currentUser, isNull);
    });
  });
}
