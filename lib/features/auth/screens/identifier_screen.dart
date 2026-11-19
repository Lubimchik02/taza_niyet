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

/// Ввод email или телефона и отправка кода.
class IdentifierScreen extends ConsumerStatefulWidget {
  const IdentifierScreen({super.key});

  @override
  ConsumerState<IdentifierScreen> createState() => _IdentifierScreenState();
}

class _IdentifierScreenState extends ConsumerState<IdentifierScreen> {
  AuthChannel _channel = AuthChannel.email;
  final _input = TextEditingController();
  bool _touched = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String? get _normalized => _channel == AuthChannel.email
      ? (AuthValidators.isEmail(_input.text) ? _input.text.trim().toLowerCase() : null)
      : AuthValidators.normalizeKzPhone(_input.text);

  Future<void> _submit() async {
    setState(() => _touched = true);
    final target = _normalized;
    if (target == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final c = await ref.read(authRepositoryProvider).sendCode(_channel, target);
      if (!mounted) return;
      ref.read(authFlowProvider.notifier).setChallenge(c);
      context.push(Routes.authOtp);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorText(context, e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final isEmail = _channel == AuthChannel.email;
    final invalid = _touched && _normalized == null;

    return AuthScaffold(
      title: l.withEmailPhone,
      children: [
        SegmentedButton<AuthChannel>(
          segments: [
            ButtonSegment(value: AuthChannel.email, label: Text(l.emailLabel), icon: const Icon(Icons.mail_outline_rounded)),
            ButtonSegment(value: AuthChannel.phone, label: Text(l.phoneLabel), icon: const Icon(Icons.phone_iphone_rounded)),
          ],
          selected: {_channel},
          onSelectionChanged: (v) => setState(() {
            _channel = v.first;
            _input.clear();
            _touched = false;
            _error = null;
          }),
        ),
        const SizedBox(height: Space.x5),
        TextField(
          controller: _input,
          enabled: !_loading,
          autofocus: true,
          keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.phone,
          autofillHints: [isEmail ? AutofillHints.email : AutofillHints.telephoneNumber],
          textInputAction: TextInputAction.done,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: isEmail ? l.emailLabel : l.phoneLabel,
            hintText: isEmail ? 'name@mail.kz' : '+7 7XX XXX XX XX',
            errorText: invalid ? (isEmail ? l.errEmail : l.errPhone) : null,
            errorMaxLines: 2,
          ),
        ),
        InlineError(_error),
      ],
      bottom: AppButton(
        label: l.getCode,
        loading: _loading,
        onPressed: _input.text.trim().isEmpty ? null : _submit,
      ),
    );
  }
}
