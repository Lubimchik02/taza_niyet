import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_x.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../auth/auth_controller.dart';
import '../org/data/org_repository.dart';
import '../org/org_controller.dart';
import '../quests/data/signup_repository.dart';
import '../quests/signups_controller.dart';
import '../shift/shift_controller.dart';
import 'data/portfolio.dart';
import 'profile_controller.dart';
import 'widgets/profile_widgets.dart';

/// Профиль: кто я, мои часы и баллы, достижения, история смен, вход в портфолио.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final c = context.colors;
    final user = ref.watch(sessionProvider);
    final m = ref.watch(membershipProvider);
    final credits = ref.watch(creditsProvider);
    final totals = ref.watch(totalsProvider);
    final shifts = credits.where((x) => x.kind == CreditKind.shift).length;
    final pending = ref.watch(mySignupsProvider).where((s) => s.shift == ShiftState.reported).toList();
    final vis = ref.watch(hoursVisibilityProvider);
    final name = user?.name ?? '';

    Widget section(String title) => Padding(
          padding: const EdgeInsets.only(top: Space.x6, bottom: Space.x2),
          child: Semantics(header: true, child: Text(title, style: context.text.titleLarge)),
        );

    return Scaffold(
      appBar: AppBar(title: Text(l.tabProfile), actions: [
        IconButton(tooltip: l.settingsTitle, icon: const Icon(Icons.settings_outlined), onPressed: () => context.push('/settings')),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.x8), children: [
        // Шапка
        Row(children: [
          ExcludeSemantics(
            child: CircleAvatar(
              radius: 32,
              backgroundColor: c.primary,
              child: Text(name.isEmpty ? '?' : name.characters.first, style: context.text.headlineMedium?.copyWith(color: c.onPrimary, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(width: Space.x4),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: context.text.headlineSmall),
              if (m != null)
                Row(children: [
                  Icon(m.status == MembershipStatus.active ? Icons.verified_rounded : Icons.hourglass_top_rounded, size: 16, color: c.primaryStrong),
                  const SizedBox(width: Space.x1),
                  Flexible(child: Text(m.status == MembershipStatus.pending ? l.orgPendingBanner(m.orgName) : m.orgName, style: context.text.bodyMedium?.copyWith(color: c.text2))),
                ]),
            ]),
          ),
        ]),
        const SizedBox(height: Space.x4),
        StatsRow(hours: totals.hours, tz: totals.tz, shifts: shifts),
        const SizedBox(height: Space.x3),
        AppCard(
          onTap: () => context.push(Routes.portfolio),
          child: Row(children: [
            Icon(Icons.qr_code_2_rounded, size: 36, color: c.primaryStrong),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.portfolioTitle, style: context.text.titleMedium),
                Text(l.portfolioCardB, style: context.text.bodyMedium?.copyWith(color: c.text2)),
              ]),
            ),
            Icon(Icons.chevron_right_rounded, color: c.text2),
          ]),
        ),

        section(l.achievementsTitle),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: Space.x2,
          crossAxisSpacing: Space.x2,
          childAspectRatio: .72,
          children: [for (final a in achievementsFor(credits)) AchievementBadge(a: a)],
        ),

        section(l.historyTitle),
        if (credits.isEmpty && pending.isEmpty)
          AppCard(
            child: Column(children: [
              Text(l.noHistoryT, style: context.text.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: Space.x1),
              Text(l.noHistoryB, style: context.text.bodyMedium?.copyWith(color: c.text2), textAlign: TextAlign.center),
              const SizedBox(height: Space.x3),
              AppButton(label: l.findQuest, kind: AppButtonKind.secondary, expand: false, onPressed: () => context.go(Routes.map)),
            ]),
          )
        else
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
            child: Column(children: [
              for (final s in pending)
                CreditTile(
                  pending: true,
                  credit: Credit(questTitle: s.quest.title, orgName: s.quest.orgName, date: s.start, hours: s.hours, tz: (s.hours * 5).round(), kind: CreditKind.shift),
                ),
              for (final cr in credits) CreditTile(credit: cr),
            ]),
          ),

        section(l.settingsShort),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(children: [
            ListTile(
              leading: Icon(Icons.visibility_outlined, color: c.primaryStrong),
              title: Text(l.visibilityTitle),
              subtitle: Text(switch (vis) { HoursVisibility.everyone => l.visAll, HoursVisibility.friends => l.visFriends, HoursVisibility.onlyMe => l.visMe }),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _pickVisibility(context, ref),
            ),
            ListTile(
              leading: Icon(Icons.groups_2_outlined, color: c.primaryStrong),
              title: Text(m?.orgName ?? l.orgTitle),
              subtitle: Text(m == null ? l.orgCardB : l.changeOrg),
              trailing: const Icon(Icons.chevron_right_rounded),
              // Смена организации — поверх профиля; текущая остаётся, пока не выбрана новая.
              onTap: () => context.push(Routes.org),
            ),
            // Демо: роль старшего. В реальном приложении её назначает координатор.
            SwitchListTile(
              value: ref.watch(seniorModeProvider),
              onChanged: (v) => ref.read(seniorModeProvider.notifier).state = v,
              title: Text(l.seniorMode),
              subtitle: Text(l.seniorModeSub),
              secondary: Icon(Icons.shield_outlined, color: c.primaryStrong),
            ),
            if (kDebugMode)
              ListTile(
                leading: Icon(Icons.palette_outlined, color: c.primaryStrong),
                title: Text(l.designSystem),
                subtitle: Text(l.designSystemSub),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.go(Routes.designSystem),
              ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _pickVisibility(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final minor = ref.read(isMinorProvider);
    final cur = ref.read(hoursVisibilityProvider);
    final v = await showModalBottomSheet<HoursVisibility>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x2), child: Text(l.visibilityTitle, style: ctx.text.titleLarge)),
          for (final (o, label) in [(HoursVisibility.everyone, l.visAll), (HoursVisibility.friends, l.visFriends), (HoursVisibility.onlyMe, l.visMe)])
            RadioListTile<HoursVisibility>(
              value: o,
              groupValue: cur,
              title: Text(label),
              // До 18 лет «Все» недоступно.
              onChanged: minor && o == HoursVisibility.everyone ? null : (x) => Navigator.pop(ctx, x),
            ),
          if (minor)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x4),
              child: Text(l.visMinorNote, style: ctx.text.bodyMedium?.copyWith(color: ctx.colors.text2)),
            ),
        ]),
      ),
    );
    if (v != null) await ref.read(hoursVisibilityProvider.notifier).set(v);
  }
}
