import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n_x.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../auth_controller.dart';
import 'auth_widgets.dart';

/// Второй фактор: 6 цифр из приложения-аутентификатора или резервный код.
class TwoFactorScreen extends ConsumerStatefulWidget {
  const TwoFactorScreen({super.key});

  @override
  ConsumerState<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends ConsumerState<TwoFactorScreen> {
  final _code = TextEditingController();
  bool _backup = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pending = ref.read(authFlowProvider).pendingUser;
    if (pending == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final u = await ref.read(authRepositoryProvider).verifySecondFactor(pending, _code.text.trim(), backup: _backup);
      if (mounted) goAfterSignIn(context, ref, u);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorText(context, e));
      _code.clear();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    if (ref.watch(authFlowProvider).pendingUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go(Routes.auth));
      return const SizedBox.shrink();
    }
    return AuthScaffold(
      title: l.twoFaTitle,
      body: _backup ? l.backupCode : l.twoFaBody,
      children: [
        if (_backup)
          TextField(
            controller: _code,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: l.backupCode, hintText: 'XXXX-XXXX'),
          )
        else
          CodeField(controller: _code, onCompleted: (_) => _submit(), hasError: _error != null, enabled: !_loading),
        InlineError(_error),
        const SizedBox(height: Space.x4),
        Center(
          child: TextButton(
            onPressed: () => setState(() {
              _backup = !_backup;
              _code.clear();
              _error = null;
            }),
            style: TextButton.styleFrom(minimumSize: const Size(Hit.min, Hit.min)),
            child: Text(_backup ? l.twoFaBody : l.useBackupCode, textAlign: TextAlign.center),
          ),
        ),
      ],
      bottom: AppButton(
        label: l.confirm,
        loading: _loading,
        onPressed: _code.text.trim().length < 6 ? null : _submit,
      ),
    );
  }
}
