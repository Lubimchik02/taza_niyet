import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_x.dart';
import '../../core/router/app_router.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/haptics.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/sprout.dart';

/// Онбординг: ценность до регистрации — 3 слайда + выбор языка.
/// Разрешения здесь НЕ запрашиваются: геолокация — при первом открытии карты, push — после первой записи.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  int _index = 0;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await ref.read(settingsProvider.notifier).markOnboardingSeen();
    if (mounted) context.go(Routes.auth);
  }

  void _next() {
    if (_index == 2) {
      _finish();
      return;
    }
    _page.nextPage(duration: Motion.of(context, Motion.slow), curve: Motion.curve);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final slides = [
      (l.ob1Title, l.ob1Body, const _MapArt()),
      (l.ob2Title, l.ob2Body, const _TeamArt()),
      (l.ob3Title, l.ob3Body, const _PortfolioArt()),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          // Верхняя строка: язык и «Пропустить»
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x2, 0),
            child: Row(children: [
              const Expanded(child: _LanguagePicker()),
              if (_index < 2)
                TextButton(
                  onPressed: _finish,
                  style: TextButton.styleFrom(minimumSize: const Size(Hit.min, Hit.min), foregroundColor: c.text2),
                  child: Text(l.skip),
                ),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _page,
              itemCount: slides.length,
              onPageChanged: (i) {
                Haptics.play(HapticKind.light);
                setState(() => _index = i);
              },
              itemBuilder: (context, i) {
                final (title, body, art) = slides[i];
                return Semantics(
                  label: l.obPage(i + 1),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: Space.x6, vertical: Space.x4),
                    child: Column(children: [
                      const SizedBox(height: Space.x6),
                      ExcludeSemantics(child: SizedBox(height: 240, child: Center(child: art))),
                      const SizedBox(height: Space.x8),
                      Semantics(header: true, child: Text(title, textAlign: TextAlign.center, style: context.text.headlineMedium)),
                      const SizedBox(height: Space.x3),
                      Text(body, textAlign: TextAlign.center, style: context.text.bodyLarge?.copyWith(color: c.text2)),
                    ]),
                  ),
                );
              },
            ),
          ),
          // Точки-индикатор (смысл дублируется текстом «Слайд N из 3» для VoiceOver)
          ExcludeSemantics(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < slides.length; i++)
                  AnimatedContainer(
                    duration: Motion.of(context, Motion.base),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: i == _index ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: i == _index ? c.primary : c.outline,
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.x4),
            child: AppButton(label: _index == 2 ? l.start : l.next, onPressed: _next),
          ),
        ]),
      ),
    );
  }
}

/// Выбор языка. Названия языков не переводятся.
class _LanguagePicker extends ConsumerWidget {
  const _LanguagePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = Localizations.localeOf(context).languageCode;
    const langs = [('kk', 'Қаз'), ('ru', 'Рус'), ('en', 'Eng')];
    return Semantics(
      label: context.l.language,
      child: Wrap(spacing: Space.x2, children: [
        for (final (code, label) in langs)
          ChoiceChip(
            label: Text(label),
            selected: current == code,
            showCheckmark: false,
            onSelected: (_) {
              Haptics.play(HapticKind.light);
              ref.read(settingsProvider.notifier).setLocale(Locale(code));
            },
          ),
      ]),
    );
  }
}

/// Слайд 1: карта с метками квестов.
class _MapArt extends StatelessWidget {
  const _MapArt();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget pin(double x, double y, {bool big = false}) => Positioned(
          left: x,
          top: y,
          child: Icon(Icons.location_on_rounded, size: big ? 52 : 36, color: big ? c.primary : c.primaryStrong),
        );
    return Container(
      width: 260,
      height: 200,
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(Radii.lg)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        Positioned(left: 0, right: 0, top: 70, child: Container(height: 14, color: c.surface)),
        Positioned(top: 0, bottom: 0, left: 150, child: Container(width: 14, color: c.surface)),
        Positioned(left: -20, top: 140, child: Transform.rotate(angle: -0.3, child: Container(width: 320, height: 22, color: c.lime))),
        pin(40, 26),
        pin(196, 110),
        pin(104, 84, big: true),
      ]),
    );
  }
}

/// Слайд 2: команда и сообщение в чате.
class _TeamArt extends StatelessWidget {
  const _TeamArt();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget av(String s, Color bg) => CircleAvatar(
          radius: 30,
          backgroundColor: bg,
          child: Text(s, style: context.text.titleMedium?.copyWith(color: c.onPrimary)),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        av('Д', c.lime),
        const SizedBox(width: Space.x2),
        av('А', c.primary),
        const SizedBox(width: Space.x2),
        av('Е', c.lime),
      ]),
      const SizedBox(height: Space.x5),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(Radii.md),
            topRight: Radius.circular(Radii.md),
            bottomRight: Radius.circular(Radii.md),
            bottomLeft: Radius.circular(4),
          ),
          boxShadow: context.isDark ? null : Shadows.e2,
        ),
        child: Text('🧤 9:50 · 🌳', style: context.text.titleMedium),
      ),
    ]);
  }
}

/// Слайд 3: росток, часы и баллы Tz, QR.
class _PortfolioArt extends StatelessWidget {
  const _PortfolioArt();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      const SproutIllustration(size: 150),
      const SizedBox(height: Space.x3),
      AppCard(
        padding: const EdgeInsets.symmetric(horizontal: Space.x5, vertical: Space.x3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(context.l.hoursShort(3), style: context.text.titleLarge),
          const SizedBox(width: Space.x3),
          const TzBadge(amount: 15),
          const SizedBox(width: Space.x3),
          Icon(Icons.qr_code_2_rounded, size: 32, color: c.text),
        ]),
      ),
    ]);
  }
}
