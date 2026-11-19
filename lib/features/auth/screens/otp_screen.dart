import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n_x.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../auth_controller.dart';
import '../data/auth_repository.dart';
import '../data/validators.dart';
import 'auth_widgets.dart';

/// Ввод 6-значного кода: автоотправка, таймер повторной отправки, понятные ошибки.
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _code = TextEditingController();
  Timer? _timer;
  int _left = 0;
  bool _loading = false;
  bool _locked = false;
  String? _error;

  OtpChallenge? get _challenge => ref.read(authFlowProvider).challenge;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    void tick() {
      final c = _challenge;
      final s = c == null ? 0 : c.resendAt.difference(DateTime.now()).inSeconds;
      if (mounted) setState(() => _left = s < 0 ? 0 : s);
      if (s <= 0) _timer?.cancel();
    }

    tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify(String code) async {
    final c = _challenge;
    if (c == null || _loading || _locked) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await ref.read(authRepositoryProvider).verifyCode(c, code);
      if (!mounted) return;
      if (r is SignedIn) {
        goAfterSignIn(context, ref, r.user);
      } else if (r is NeedsSecondFactor) {
        ref.read(authFlowProvider.notifier).setPending(r.pendingUser);
        context.push(Routes.auth2fa);
      }
    } on AuthFailure catch (e) {
      if (!mounted) return;
      if (e.attemptsLeft != null) {
        ref.read(authFlowProvider.notifier).setChallenge(c.copyWith(attemptsLeft: e.attemptsLeft));
      }
      setState(() {
        _error = authErrorText(context, e);
        _locked = e.kind == AuthFailureKind.tooManyAttempts;
      });
      _code.clear();
    } catch (e) {
      if (mounted) setState(() => _error = authErrorText(context, e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    final c = _challenge;
    if (c == null) return;
    setState(() => _error = null);
    try {
      final n = await ref.read(authRepositoryProvider).sendCode(c.channel, c.target);
      ref.read(authFlowProvider.notifier).setChallenge(n);
      _code.clear();
      setState(() => _locked = false);
      _startTimer();
    } catch (e) {
      if (mounted) setState(() => _error = authErrorText(context, e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = ref.watch(authFlowProvider).challenge;
    if (c == null) {
      // Открыли экран без отправленного кода (например, по ссылке) — назад к вводу.
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go(Routes.authIdentifier));
      return const SizedBox.shrink();
    }
    final shown = c.channel == AuthChannel.phone ? AuthValidators.formatKzPhone(c.target) : c.target;

    return AuthScaffold(
      title: l.otpTitle,
      body: l.otpSentTo(shown),
      children: [
        CodeField(controller: _code, onCompleted: _verify, hasError: _error != null, enabled: !_loading && !_locked),
        InlineError(_error),
        const SizedBox(height: Space.x6),
        Center(
          child: _left > 0
              ? Text(l.resendIn(_left), style: Theme.of(context).textTheme.bodyMedium)
              : TextButton(
                  onPressed: _resend,
                  style: TextButton.styleFrom(minimumSize: const Size(Hit.min, Hit.min)),
                  child: Text(l.resend),
                ),
        ),
        Center(
          child: TextButton(
            onPressed: () => context.pop(),
            style: TextButton.styleFrom(minimumSize: const Size(Hit.min, Hit.min)),
            child: Text(l.changeTarget),
          ),
        ),
      ],
      bottom: AppButton(
        label: l.confirm,
        loading: _loading,
        onPressed: _locked || _code.text.length < 6 ? null : () => _verify(_code.text),
      ),
    );
  }
}
