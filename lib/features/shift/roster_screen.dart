import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n_x.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/haptics.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../auth/auth_controller.dart';
import '../quests/data/signup_repository.dart';
import '../quests/signups_controller.dart';
import 'data/shift_repository.dart';
import 'shift_controller.dart';
import 'widgets/hours_format.dart';

/// Экран старшего: кто пришёл, сколько часов засчитать, «Закрыть смену».
/// Защита от «любимчиков»: часы не больше длительности квеста, ручные отметки
/// помечены и видны координатору отдельно, бонус старшему — только после проверки.
class RosterScreen extends ConsumerStatefulWidget {
  const RosterScreen({super.key, required this.questId});
  final String questId;

  @override
  ConsumerState<RosterScreen> createState() => _RosterScreenState();
}

class _RosterScreenState extends ConsumerState<RosterScreen> {
  List<RosterMember>? _members;
  Object? _error;
  bool _sending = false;

  Signup? get _mine => ref.read(mySignupsProvider.notifier).forQuest(widget.questId);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = _mine;
    if (s?.team == null) return;
    setState(() => _error = null);
    try {
      final list = await ref.read(shiftRepositoryProvider).roster(s!.quest, s.team!, myName: ref.read(sessionProvider)?.name ?? '', mine: s);
      if (mounted) setState(() => _members = list);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _toggle(RosterMember m) {
    if (m.checkedInAt != null) return; // отметку по геометке старший не снимает
    Haptics.play(HapticKind.light);
    setState(() => _members = [for (final x in _members!) x.id == m.id ? x.copyWith(markedBySenior: !x.markedBySenior) : x]);
  }

  Future<void> _editHours(RosterMember m) async {
    final q = _mine!.quest;
    final max = q.duration.inMinutes / 60;
    var h = m.hours;
    final l = context.l;
    final res = await showModalBottomSheet<double>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x4),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.editHoursT, style: ctx.text.titleLarge),
              Text('${m.name} · ${l.editHoursB(formatHours(ctx, max))}', style: ctx.text.bodyMedium?.copyWith(color: ctx.colors.text2)),
              const SizedBox(height: Space.x4),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton.filledTonal(tooltip: '−0,5', onPressed: h <= 0 ? null : () => set(() => h = clampHours(h - .5, q)), icon: const Icon(Icons.remove_rounded)),
                SizedBox(width: 120, child: Text(formatHours(ctx, h), textAlign: TextAlign.center, style: ctx.text.headlineMedium)),
                IconButton.filledTonal(tooltip: '+0,5', onPressed: h >= max ? null : () => set(() => h = clampHours(h + .5, q)), icon: const Icon(Icons.add_rounded)),
              ]),
              const SizedBox(height: Space.x4),
              AppButton(label: l.done, onPressed: () => Navigator.pop(ctx, h)),
            ]),
          ),
        ),
      ),
    );
    if (res != null) setState(() => _members = [for (final x in _members!) x.id == m.id ? x.copyWith(hours: res) : x]);
  }

  Future<void> _close() async {
    final l = context.l;
    final s = _mine!;
    final report = ShiftReport(questId: s.quest.id, teamId: s.team!.id, members: _members!);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x4),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l.closeShiftT, style: ctx.text.titleLarge),
            const SizedBox(height: Space.x2),
            Text(l.closeShiftSummary(report.presentCount, report.absentCount, formatHours(ctx, report.totalHours)), style: ctx.text.bodyLarge),
            if (report.manualCount > 0) ...[
              const SizedBox(height: Space.x2),
              Text(l.manualMarksNote(report.manualCount), style: ctx.text.bodyMedium?.copyWith(color: ctx.colors.warning)),
            ],
            const SizedBox(height: Space.x3),
            Text(l.closeShiftNote, style: ctx.text.bodyMedium?.copyWith(color: ctx.colors.text2)),
            const SizedBox(height: Space.x4),
            AppButton(label: l.closeShift, onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final done = ref.read(shiftControllerProvider.notifier).close(report, questTitle: s.quest.title, date: s.start, orgName: s.quest.orgName);
    // Отчёт ушёл — сообщаем сразу; одобрение придёт позже (пуш на этапе 11).
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    setState(() => _sending = false);
    Haptics.play(HapticKind.success);
    messenger.showSnackBar(SnackBar(content: Text(l.shiftSent)));
    done.then((_) => messenger.showSnackBar(SnackBar(content: Text(l.shiftApprovedSenior))));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final s = ref.watch(mySignupsProvider.select((all) => all.where((x) => x.quest.id == widget.questId).firstOrNull));
    final status = ref.watch(shiftControllerProvider)[widget.questId];
    final members = _members;

    return Scaffold(
      appBar: AppBar(title: Text(s?.team == null ? l.openRoster : l.teamN(s!.team!.number))),
      body: _error != null
          ? ErrorState(title: l.errorNetworkTitle, body: l.errorNetworkBody, retryLabel: l.retry, onRetry: _load)
          : members == null
              ? ListView(padding: const EdgeInsets.all(Space.screen), children: const [SkeletonListTile(), SkeletonListTile(), SkeletonListTile()])
              : ListView(padding: const EdgeInsets.all(Space.screen), children: [
                  Text(s?.quest.title ?? '', style: context.text.titleLarge),
                  const SizedBox(height: Space.x1),
                  Text(l.rosterHint, style: context.text.bodyMedium?.copyWith(color: c.text2)),
                  const SizedBox(height: Space.x3),
                  Semantics(
                    liveRegion: true,
                    child: Text(l.presentCount(members.where((m) => m.present).length, members.length), style: context.text.titleMedium),
                  ),
                  const SizedBox(height: Space.x2),
                  for (final m in members)
                    _MemberTile(member: m, locked: status != null, onToggle: () => _toggle(m), onHours: () => _editHours(m)),
                  if (status != null) ...[
                    const SizedBox(height: Space.x3),
                    Container(
                      padding: const EdgeInsets.all(Space.x4),
                      decoration: BoxDecoration(color: c.lime, borderRadius: BorderRadius.circular(Radii.md)),
                      child: Row(children: [
                        Icon(status == ReportStatus.approved ? Icons.workspace_premium_rounded : Icons.hourglass_top_rounded, color: c.primaryStrong),
                        const SizedBox(width: Space.x3),
                        Expanded(child: Text(status == ReportStatus.approved ? l.shiftApprovedSenior : l.shiftSent, style: context.text.bodyLarge)),
                      ]),
                    ),
                  ],
                ]),
      bottomNavigationBar: members == null || status != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.x4, Space.x2, Space.x4, Space.x3),
                child: AppButton(label: l.closeShift, loading: _sending, onPressed: _sending ? null : _close),
              ),
            ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.locked, required this.onToggle, required this.onHours});
  final RosterMember member;
  final bool locked;
  final VoidCallback onToggle, onHours;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final m = member;
    final (IconData icon, String sub) = m.checkedInAt != null
        ? (m.geoVerified ? Icons.where_to_vote_rounded : Icons.location_off_outlined, m.geoVerified ? l.markedGeo : l.geoManual)
        : m.markedBySenior
            ? (Icons.back_hand_outlined, l.markedBySenior)
            : (Icons.radio_button_unchecked_rounded, l.notArrived);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.x2),
      child: Material(
        color: m.present ? c.surface : c.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md), side: BorderSide(color: c.outline)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.md),
          onTap: locked || m.checkedInAt != null ? null : onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x3),
            child: Row(children: [
              Icon(icon, color: m.present ? c.primaryStrong : c.text2),
              const SizedBox(width: Space.x3),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text.rich(TextSpan(children: [
                    TextSpan(text: m.isMe ? '${m.name} (${l.youLabel})' : m.name, style: context.text.titleMedium),
                    if (m.minor) TextSpan(text: '  ${l.minorTag}', style: context.text.labelSmall?.copyWith(color: c.text2)),
                  ])),
                  Text(sub, style: context.text.bodyMedium?.copyWith(color: c.text2)),
                ]),
              ),
              if (m.present)
                TextButton(
                  onPressed: locked ? null : onHours,
                  child: Text(formatHours(context, m.hours)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
