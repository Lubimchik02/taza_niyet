import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_x.dart';
import '../../core/router/app_router.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';

/// Каталог компонентов во всех состояниях. Только для разработки (debug).
class DesignSystemScreen extends ConsumerStatefulWidget {
  const DesignSystemScreen({super.key});

  @override
  ConsumerState<DesignSystemScreen> createState() => _DesignSystemScreenState();
}

class _DesignSystemScreenState extends ConsumerState<DesignSystemScreen> {
  bool _loading = false;
  bool _offline = false;
  bool _showError = false;
  final _chips = <int>{0};
  final _email = TextEditingController(text: 'arman.mail.kz');

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _fakeSubmit() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l.done)));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final s = ref.watch(settingsProvider);
    final ctl = ref.read(settingsProvider.notifier);
    final emailError = _email.text.contains('@') ? null : l.emailInvalid;

    Widget h(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(4, Space.x6, 4, Space.x2),
          child: Semantics(header: true, child: Text(t.toUpperCase(), style: context.text.labelSmall?.copyWith(color: c.text2))),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.designSystem)),
      body: Column(children: [
        if (_offline) OfflineBanner(message: l.offlineBanner),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(Space.screen), children: [
            h(l.theme),
            SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text(l.themeSystem)),
                ButtonSegment(value: ThemeMode.light, label: Text(l.themeLight)),
                ButtonSegment(value: ThemeMode.dark, label: Text(l.themeDark)),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => ctl.setThemeMode(v.first),
            ),
            h(l.language),
            // Названия языков не переводятся.
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'kk', label: Text('Қазақша')),
                ButtonSegment(value: 'ru', label: Text('Русский')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {Localizations.localeOf(context).languageCode},
              onSelectionChanged: (v) => ctl.setLocale(Locale(v.first)),
            ),
            const SizedBox(height: Space.x4),
            AppButton(
              label: l.replayOnboarding,
              kind: AppButtonKind.secondary,
              icon: Icons.replay_rounded,
              onPressed: () async {
                await ctl.resetOnboarding();
                if (context.mounted) context.go(Routes.splash);
              },
            ),
            h('Кнопки / Buttons'),
            AppButton(label: l.findQuest, loading: _loading, onPressed: _fakeSubmit),
            const SizedBox(height: Space.x3),
            AppButton(label: l.findQuest, onPressed: null),
            const SizedBox(height: Space.x3),
            AppButton(label: l.retry, kind: AppButtonKind.secondary, icon: Icons.refresh_rounded, onPressed: () {}),
            const SizedBox(height: Space.x3),
            AppButton(label: l.back, kind: AppButtonKind.ghost, onPressed: () {}),
            const SizedBox(height: Space.x3),
            AppButton(label: 'Delete account', kind: AppButtonKind.danger, onPressed: () {}),
            h('Поля / Inputs'),
            const TextField(decoration: InputDecoration(labelText: 'Имя / Name')),
            const SizedBox(height: Space.x3),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: 'Email', errorText: emailError),
            ),
            const SizedBox(height: Space.x3),
            const TextField(enabled: false, decoration: InputDecoration(labelText: 'Disabled')),
            h('Чипы / Chips'),
            Wrap(spacing: Space.x2, runSpacing: Space.x2, children: [
              for (final (i, label) in ['Рядом', 'Эта неделя', 'Лёгкие'].indexed)
                FilterChip(
                  label: Text(label),
                  selected: _chips.contains(i),
                  onSelected: (v) => setState(() => v ? _chips.add(i) : _chips.remove(i)),
                ),
            ]),
            h('Карточка, Tz / Card, Tz'),
            AppCard(
              onTap: () {},
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Уборка набережной Ишима', style: context.text.titleMedium),
                    const SizedBox(height: Space.x1),
                    Text('Сб, 21 ноя · 10:00 · 1,2 км', style: context.text.bodyMedium?.copyWith(color: c.text2)),
                  ]),
                ),
                TzBadge(amount: 15, semanticsLabel: l.tzSemantics(15)),
              ]),
            ),
            h('Типографика / Type'),
            Text(l.hoursShort(38), style: context.text.displaySmall),
            Text('Title 1', style: context.text.headlineMedium),
            Text('Title 2', style: context.text.titleLarge),
            Text('Headline', style: context.text.titleMedium),
            Text('Body — Taza Niyet', style: context.text.bodyLarge),
            Text('Caption', style: context.text.labelSmall),
            h('Скелетон / Skeleton'),
            const SkeletonListTile(),
            h('Состояния / States'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l.offlineBanner),
              value: _offline,
              onChanged: (v) => setState(() => _offline = v),
            ),
            SizedBox(
              height: 320,
              child: AppCard(
                child: _showError
                    ? ErrorState(
                        title: l.errorNetworkTitle,
                        body: l.errorNetworkBody,
                        retryLabel: l.retry,
                        onRetry: () => setState(() => _showError = false),
                      )
                    : EmptyState(
                        title: l.emptyQuestsTitle,
                        body: l.emptyQuestsBody,
                        actionLabel: l.errorNetworkTitle,
                        onAction: () => setState(() => _showError = true),
                      ),
              ),
            ),
            const SizedBox(height: Space.x10),
          ]),
        ),
      ]),
    );
  }
}
