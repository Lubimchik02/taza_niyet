import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n_x.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../auth_controller.dart';
import '../data/validators.dart';
import 'auth_widgets.dart';

/// Новый пользователь: имя и год рождения (от возраста зависят настройки приватности).
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _name = TextEditingController();
  int? _year;
  bool _touched = false;
  bool _loading = false;
  bool _consent = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickYear() async {
    final now = DateTime.now().year;
    // Самый поздний год — тот, при котором точно исполнилось 13 (по худшему случаю).
    final years = [for (var y = now - AuthValidators.minAge - 1; y >= now - 90; y--) y];
    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 360,
          child: ListView.builder(
            itemCount: years.length,
            itemBuilder: (_, i) => ListTile(
              minTileHeight: Hit.min,
              title: Text('${years[i]}', textAlign: TextAlign.center),
              selected: years[i] == _year,
              onTap: () => Navigator.pop(context, years[i]),
            ),
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _year = picked);
  }

  Future<void> _submit() async {
    setState(() => _touched = true);
    final user = ref.read(sessionProvider);
    if (user == null || !AuthValidators.isName(_name.text) || _year == null || !_consent) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final u = await ref.read(authRepositoryProvider).completeProfile(user, name: _name.text, birthYear: _year!);
      if (mounted) goAfterSignIn(context, ref, u);
    } catch (e) {
      if (mounted) setState(() => _error = authErrorText(context, e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final nameErr = _touched && !AuthValidators.isName(_name.text);
    final yearErr = _touched && _year == null;
    final minor = _year != null && AuthValidators.isMinor(_year!);

    return PopScope(
      canPop: false, // профиль обязателен
      child: AuthScaffold(
        showBack: false,
        title: l.profileTitle,
        body: l.profileBody,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: l.nameLabel, errorText: nameErr ? l.errName : null),
          ),
          const SizedBox(height: Space.x4),
          Semantics(
            button: true,
            label: '${l.birthYear}: ${_year ?? '—'}',
            excludeSemantics: true,
            child: InkWell(
              onTap: _pickYear,
              borderRadius: BorderRadius.circular(Radii.sm),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: l.birthYear,
                  errorText: yearErr ? l.errYear : null,
                  suffixIcon: const Icon(Icons.expand_more_rounded),
                ),
                child: Text(_year?.toString() ?? '', style: context.text.bodyLarge),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, Space.x2, 4, 0),
            child: Text('${l.birthYearHint} ${l.minAgeNote}.', style: context.text.labelSmall?.copyWith(color: c.text2)),
          ),
          if (minor) ...[
            const SizedBox(height: Space.x4),
            AppCard(
              child: Row(children: [
                Icon(Icons.shield_outlined, color: c.primaryStrong),
                const SizedBox(width: Space.x3),
                Expanded(child: Text(l.minorNote, style: context.text.bodyMedium)),
              ]),
            ),
          ],
          const SizedBox(height: Space.x4),
          // Согласие на обработку персональных данных (Закон РК): без него профиль не создаём.
          // Время и версия текста сохраняются на сервере (profiles.consent_at / consent_version).
          CheckboxListTile(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: Text(l.consentText, style: context.text.bodyMedium),
            subtitle: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero, alignment: Alignment.centerLeft, minimumSize: const Size(0, 36)),
              onPressed: () => launchUrl(Uri.parse('https://tazaniyet.kz/privacy'), mode: LaunchMode.externalApplication),
              child: Text(l.privacyPolicy),
            ),
          ),
          if (minor) Text(l.consentMinor, style: context.text.bodySmall?.copyWith(color: c.text2)),
          if (_touched && !_consent) InlineError(l.consentRequired),
          InlineError(_error),
        ],
        bottom: AppButton(label: l.continueAction, loading: _loading, onPressed: _submit),
      ),
    );
  }
}
