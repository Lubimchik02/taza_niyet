import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n_x.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/haptics.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../auth/auth_controller.dart';
import '../auth/data/validators.dart';
import '../org/data/org_repository.dart';
import '../org/org_controller.dart';
import '../../core/geo.dart';
import '../../core/net/connectivity.dart';
import '../notifications/notifications.dart';
import '../shift/data/shift_repository.dart';
import '../shift/shift_controller.dart';
import '../shift/widgets/hours_format.dart';
import 'data/quest_repository.dart';
import 'data/signup_repository.dart';
import 'signups_controller.dart';
import 'widgets/quest_card.dart';

/// Ссылка-приглашение на квест. Universal/App Links настраиваются на этапе 11.
String questLink(String id) => 'https://tazaniyet.kz/q/$id';

/// Карточка квеста: что, когда, где, команды и запись.
/// Состояния кнопки: нет организации → вступить; заявка на рассмотрении → ждать;
/// чужая организация → только просмотр; есть места → записаться; мест нет → лист ожидания;
/// записан → пригласить друзей / отменить; в листе ожидания → выйти.
class QuestDetailScreen extends ConsumerStatefulWidget {
  const QuestDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<QuestDetailScreen> createState() => _QuestDetailScreenState();
}

class _QuestDetailScreenState extends ConsumerState<QuestDetailScreen> {
  String? _teamId;
  bool _busy = false;

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _invite(Quest q) async {
    final l = context.l;
    Haptics.play(HapticKind.light);
    await Share.share(l.inviteText(q.title, questWhen(context, q.startsAt), questLink(q.id)), subject: q.title);
  }

  Future<void> _join(Quest q, List<Team> teams) async {
    final l = context.l;
    final team = teams.where((t) => t.id == _teamId && !t.isFull).firstOrNull ?? teams.where((t) => !t.isFull).firstOrNull;
    final birth = ref.read(sessionProvider)?.birthYear;
    final minor = birth != null && AuthValidators.isMinor(birth);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x4),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.confirmJoinT, style: ctx.text.titleLarge),
            const SizedBox(height: Space.x3),
            Text(q.title, style: ctx.text.titleMedium),
            const SizedBox(height: Space.x1),
            Text('${questWhen(ctx, q.startsAt)} · ${l.hoursShort(q.duration.inHours)}\n${q.address}', style: ctx.text.bodyMedium?.copyWith(color: ctx.colors.text2)),
            if (team != null) ...[
              const SizedBox(height: Space.x1),
              Text(l.youJoinedTeam(l.teamN(team.number), team.seniorName), style: ctx.text.bodyMedium?.copyWith(color: ctx.colors.text2)),
            ] else ...[
              const SizedBox(height: Space.x2),
              Text(l.waitlistHint, style: ctx.text.bodyMedium),
            ],
            if (minor) ...[
              const SizedBox(height: Space.x3),
              Container(
                padding: const EdgeInsets.all(Space.x3),
                decoration: BoxDecoration(color: ctx.colors.lime, borderRadius: BorderRadius.circular(Radii.sm)),
                child: Row(children: [
                  Icon(Icons.family_restroom_rounded, color: ctx.colors.primaryStrong),
                  const SizedBox(width: Space.x2),
                  Expanded(child: Text(l.minorJoinNote, style: ctx.text.bodyMedium)),
                ]),
              ),
            ],
            const SizedBox(height: Space.x4),
            AppButton(label: team == null ? l.joinWaitlist : l.signUp, onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final s = await ref.read(mySignupsProvider.notifier).join(q, team: team);
      Haptics.play(HapticKind.success);
      _snack(s.status == SignupStatus.joined ? l.joinedToast : l.waitlistPos(s.position));
      if (s.status == SignupStatus.joined) await _remind(q);
    } on SignupFailure catch (e) {
      _snack(switch (e.kind) {
        SignupFailureKind.timeConflict => l.errTimeConflict,
        SignupFailureKind.alreadySigned => l.errAlreadySigned,
        _ => l.errorNetworkBody,
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// После первой записи — мягкий вопрос про уведомления, потом системный запрос.
  /// Напоминания за день и за час планируются на устройстве (работают без сети).
  Future<void> _remind(Quest q) async {
    final l = context.l;
    final push = ref.read(localNotificationsProvider);
    if (!push.asked && mounted) {
      final yes = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x4),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.notifications_active_outlined, size: 40, color: ctx.colors.primaryStrong),
              const SizedBox(height: Space.x3),
              Text(l.pushAskT, style: ctx.text.titleLarge),
              const SizedBox(height: Space.x2),
              Text(l.pushAskB, style: ctx.text.bodyMedium?.copyWith(color: ctx.colors.text2)),
              const SizedBox(height: Space.x4),
              AppButton(label: l.locAllow, onPressed: () => Navigator.pop(ctx, true)),
              AppButton(label: l.notNow, kind: AppButtonKind.ghost, onPressed: () => Navigator.pop(ctx, false)),
            ]),
          ),
        ),
      );
      if (yes == true) {
        await push.requestPermission();
      } else {
        await push.markAsked();
        return;
      }
    }
    await push.scheduleShift(q, dayText: l.nfReminderDay(q.title), hourText: l.nfReminderHour(q.title));
  }

  Future<void> _checkIn(Signup s, {bool force = false}) async {
    final l = context.l;
    setState(() => _busy = true);
    final r = await ref.read(shiftControllerProvider.notifier).checkIn(s, force: force);
    if (!mounted) return;
    setState(() => _busy = false);
    switch (r) {
      case CheckedIn(:final geoVerified):
        Haptics.play(HapticKind.success);
        _snack(!ref.read(isOnlineProvider) ? l.queuedCheckIn : (geoVerified ? l.geoOk : l.geoManual));
      case TooFar(:final km):
        final again = await showModalBottomSheet<bool>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x4),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.tooFarT(formatKm(km, Localizations.localeOf(ctx).languageCode)), style: ctx.text.titleLarge),
                const SizedBox(height: Space.x2),
                Text(l.tooFarB, style: ctx.text.bodyMedium?.copyWith(color: ctx.colors.text2)),
                const SizedBox(height: Space.x4),
                AppButton(label: l.markAnyway, kind: AppButtonKind.secondary, onPressed: () => Navigator.pop(ctx, true)),
                AppButton(label: l.later, kind: AppButtonKind.ghost, onPressed: () => Navigator.pop(ctx, false)),
              ]),
            ),
          ),
        );
        if (again == true && mounted) await _checkIn(s, force: true);
      case NeedsLocation():
        final again = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l.locNeededT),
            content: Text(l.locNeededB),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.markAnyway)),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(l.locAllow)),
            ],
          ),
        );
        if (again != null && mounted) await _checkIn(s, force: !again);
    }
  }

  Future<void> _leave(Signup s) async {
    final l = context.l;
    final late = s.status == SignupStatus.joined && s.start.difference(DateTime.now()) < const Duration(hours: 24);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.status == SignupStatus.joined ? l.cancelConfirmT : l.leaveWaitlist),
        content: Text(late ? '${l.cancelConfirmB}\n\n${l.lateCancelWarn}' : l.cancelConfirmB),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l.keep)),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: ctx.colors.danger),
            child: Text(s.status == SignupStatus.joined ? l.cancelSignup : l.leaveWaitlist),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(mySignupsProvider.notifier).leave(s);
    } catch (_) {
      _snack(l.errorNetworkBody);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final quest = ref.watch(questByIdProvider(widget.id));
    return quest.when(
      loading: () => Scaffold(
        appBar: AppBar(),
        body: ListView(padding: const EdgeInsets.all(Space.screen), children: const [SkeletonListTile(), SkeletonListTile(), SkeletonListTile()]),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(title: l.errorNetworkTitle, body: l.errorNetworkBody, retryLabel: l.retry, onRetry: () => ref.invalidate(questByIdProvider(widget.id))),
      ),
      data: (q) => q == null
          ? Scaffold(appBar: AppBar(), body: EmptyState(title: l.questNotFound, body: l.questNotFoundB, actionLabel: l.findQuest, onAction: () => context.go(Routes.map)))
          : _body(q),
    );
  }

  Widget _body(Quest q) {
    final l = context.l;
    final c = context.colors;
    final teams = ref.watch(teamsProvider(q.id));
    final mine = ref.watch(mySignupsProvider.select((all) => all.where((s) => s.quest.id == q.id).firstOrNull));
    final m = ref.watch(membershipProvider);

    return Scaffold(
      appBar: AppBar(actions: [
        if (mine?.team != null)
          IconButton(tooltip: l.teamChatLabel(l.teamN(mine!.team!.number)), icon: const Icon(Icons.forum_outlined), onPressed: () => context.push('/chat/team-${mine.team!.id}')),
        IconButton(tooltip: l.inviteFriends, icon: const Icon(Icons.ios_share_rounded), onPressed: () => _invite(q)),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.x6), children: [
        Semantics(header: true, child: Text(q.title, style: context.text.headlineSmall)),
        const SizedBox(height: Space.x1),
        Row(children: [
          Icon(Icons.verified_rounded, size: 18, color: c.primaryStrong),
          const SizedBox(width: Space.x1),
          Text(q.orgName, style: context.text.bodyMedium?.copyWith(color: c.text2)),
        ]),
        const SizedBox(height: Space.x3),
        Wrap(spacing: Space.x3, runSpacing: Space.x2, crossAxisAlignment: WrapCrossAlignment.center, children: [
          TzBadge(amount: q.maxTz, semanticsLabel: l.upToTz(q.maxTz)),
          DifficultyDots(q.difficulty),
        ]),
        if (mine != null) ...[const SizedBox(height: Space.x4), _StatusCard(signup: mine, senior: ref.watch(seniorModeProvider))],
        const SizedBox(height: Space.x4),
        _InfoRow(icon: Icons.event_rounded, label: l.whenLabel, value: '${questWhen(context, (mine?.quest ?? q).startsAt)} · ${l.hoursShort(q.duration.inHours)}'),
        _InfoRow(icon: Icons.place_outlined, label: l.whereLabel, value: q.address),
        const SizedBox(height: Space.x4),
        Text(l.aboutQuest, style: context.text.titleMedium),
        const SizedBox(height: Space.x1),
        Text(q.description, style: context.text.bodyLarge),
        const SizedBox(height: Space.x6),
        Text(l.teamsTitle, style: context.text.titleMedium),
        const SizedBox(height: Space.x2),
        teams.when(
          loading: () => const Column(children: [SkeletonListTile(), SkeletonListTile()]),
          error: (_, __) => ErrorState(title: l.errorNetworkTitle, body: l.errorNetworkBody, retryLabel: l.retry, onRetry: () => ref.invalidate(teamsProvider(q.id))),
          data: (list) {
            final canPick = mine == null && m?.status == MembershipStatus.active && m?.orgId == q.orgId;
            final selected = _teamId ?? list.where((t) => !t.isFull).firstOrNull?.id;
            return Column(children: [
              for (final t in list)
                _TeamTile(
                  team: t,
                  selected: canPick && t.id == selected,
                  mine: mine?.team?.id == t.id,
                  onTap: canPick && !t.isFull ? () => setState(() => _teamId = t.id) : null,
                ),
            ]);
          },
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x3),
          child: _action(q, mine, m, teams.valueOrNull ?? const []),
        ),
      ),
    );
  }

  /// Нижняя кнопка — по состоянию волонтёра и квеста.
  Widget _action(Quest q, Signup? mine, Membership? m, List<Team> teams) {
    final l = context.l;
    final c = context.colors;
    Widget note(String text) => Padding(
          padding: const EdgeInsets.only(bottom: Space.x2),
          child: Text(text, textAlign: TextAlign.center, style: context.text.bodyMedium?.copyWith(color: c.text2)),
        );

    if (mine != null && mine.status == SignupStatus.joined) return _shiftAction(mine);
    if (mine != null) {
      return AppButton(label: l.leaveWaitlist, kind: AppButtonKind.ghost, loading: _busy, onPressed: _busy ? null : () => _leave(mine));
    }
    if (m == null || m.status == MembershipStatus.rejected) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        note(l.noOrgMapNote),
        AppButton(label: l.joinOrgToSignUp, kind: AppButtonKind.secondary, onPressed: () => context.push(Routes.org)),
      ]);
    }
    if (m.status == MembershipStatus.pending) {
      return Column(mainAxisSize: MainAxisSize.min, children: [note(l.pendingJoinNote(m.orgName)), AppButton(label: l.signUp, onPressed: null)]);
    }
    if (m.orgId != q.orgId) {
      return Column(mainAxisSize: MainAxisSize.min, children: [note(l.otherOrgNote(q.orgName)), AppButton(label: l.inviteFriends, kind: AppButtonKind.secondary, onPressed: () => _invite(q))]);
    }
    final full = teams.isNotEmpty && teams.every((t) => t.isFull);
    return AppButton(
      label: full ? l.joinWaitlist : l.signUp,
      kind: full ? AppButtonKind.secondary : AppButtonKind.primary,
      loading: _busy,
      onPressed: _busy || teams.isEmpty ? null : () => _join(q, teams),
    );
  }
}

extension on _QuestDetailScreenState {
  /// Кнопки записанного волонтёра: до смены — пригласить/отменить; во время — «Я на месте»;
  /// после отметки — ждать старшего (или открыть список команды, если вы старший).
  Widget _shiftAction(Signup mine) {
    final l = context.l;
    final c = context.colors;
    final senior = ref.watch(seniorModeProvider);
    final w = checkInWindow(mine.quest, DateTime.now());
    final roster = AppButton(
      label: l.openRoster,
      icon: Icons.fact_check_outlined,
      kind: AppButtonKind.secondary,
      onPressed: () => context.push('/quest/${mine.quest.id}/team'),
    );
    final demo = kDebugMode;
    if (mine.shift != ShiftState.open) return const SizedBox.shrink();
    if (w == CheckInWindow.notYet) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        AppButton(label: l.inviteFriends, icon: Icons.person_add_alt_rounded, onPressed: () => _invite(mine.quest)),
        AppButton(label: l.cancelSignup, kind: AppButtonKind.ghost, loading: _busy, onPressed: _busy ? null : () => _leave(mine)),
        if (demo)
          TextButton(onPressed: () => ref.read(mySignupsProvider.notifier).demoStartNow(mine.quest.id), child: Text(l.demoShiftNow)),
      ]);
    }
    if (mine.checkedInAt == null && w == CheckInWindow.open) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        AppButton(label: l.imHere, icon: Icons.where_to_vote_rounded, loading: _busy, onPressed: _busy ? null : () => _checkIn(mine)),
        if (senior) roster,
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      if (mine.checkedInAt == null)
        Padding(
          padding: const EdgeInsets.only(bottom: Space.x2),
          child: Text(l.shiftEnded, style: context.text.bodyMedium?.copyWith(color: c.text2)),
        ),
      if (senior) roster,
      if (!senior && demo)
        TextButton(onPressed: () => ref.read(shiftControllerProvider.notifier).simulateSeniorClose(mine), child: Text(l.demoSeniorClosed)),
    ]);
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.signup, this.senior = false});
  final Signup signup;
  final bool senior;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final s = signup;
    final joined = s.status == SignupStatus.joined;
    final (IconData icon, Color tint, String title, String body) = !joined
        ? (Icons.hourglass_top_rounded, c.warning, l.waitlistPos(s.position), l.waitlistHint)
        : switch (s.shift) {
            ShiftState.approved => (Icons.workspace_premium_rounded, c.primaryStrong, l.shiftApproved(formatHours(context, s.hours), tzForHours(s.hours)), s.quest.title),
            ShiftState.reported => (Icons.hourglass_top_rounded, c.warning, l.shiftReported(formatHours(context, s.hours)), l.shiftBySenior),
            ShiftState.missed => (Icons.info_outline_rounded, c.warning, l.notArrived, l.shiftMissed),
            ShiftState.open when s.checkedInAt != null => (
                s.geoVerified ? Icons.where_to_vote_rounded : Icons.back_hand_outlined,
                c.primaryStrong,
                l.checkedInAt(TimeOfDay.fromDateTime(s.checkedInAt!).format(context)),
                '${s.geoVerified ? l.geoOk : l.geoManual}. ${l.shiftBySenior}',
              ),
            _ => (
                Icons.check_circle_rounded,
                c.primaryStrong,
                l.youJoined,
                [
                  l.youJoinedTeam(l.teamN(s.team!.number), senior ? l.youLabel : s.team!.seniorName),
                  if (checkInWindow(s.quest, DateTime.now()) == CheckInWindow.notYet) l.checkInSoon,
                ].join('. '),
              ),
          };
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(Space.x4),
        decoration: BoxDecoration(color: joined && s.shift != ShiftState.missed ? c.lime : c.surface2, borderRadius: BorderRadius.circular(Radii.md)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: tint),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (senior && joined) Text(l.youAreSenior(s.team!.number), style: context.text.labelMedium?.copyWith(color: c.primaryStrong)),
              Text(title, style: context.text.titleMedium),
              const SizedBox(height: Space.x1),
              Text(body, style: context.text.bodyMedium?.copyWith(color: c.text2)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label, value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.x2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, color: context.colors.primaryStrong),
            const SizedBox(width: Space.x3),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: context.text.labelMedium?.copyWith(color: context.colors.text2)),
                Text(value, style: context.text.bodyLarge),
              ]),
            ),
          ]),
        ),
      );
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({required this.team, required this.selected, required this.mine, this.onTap});
  final Team team;
  final bool selected, mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final t = team;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x2),
      child: Semantics(
        selected: selected || mine,
        inMutuallyExclusiveGroup: true,
        child: Material(
          color: selected || mine ? c.lime : c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
            side: BorderSide(color: selected || mine ? c.primary : c.outline, width: selected || mine ? 2 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.md),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Hit.min + 16),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l.teamN(t.number), style: context.text.titleMedium),
                      Text(l.seniorLabel(t.seniorName), style: context.text.bodyMedium?.copyWith(color: c.text2)),
                    ]),
                  ),
                  Text(
                    t.isFull ? l.teamFull : l.spotsLeft(t.spotsLeft, t.capacity),
                    style: context.text.labelMedium?.copyWith(color: t.isFull ? c.warning : c.text2),
                  ),
                  if (selected || mine) ...[const SizedBox(width: Space.x2), Icon(Icons.check_circle_rounded, color: c.primaryStrong, size: 20)],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
