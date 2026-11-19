import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/geo.dart';
import '../../core/l10n_x.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/haptics.dart';
import '../../core/widgets/app_button.dart';
import '../../core/widgets/app_card.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../org/data/org_repository.dart';
import '../org/org_controller.dart';
import '../quests/data/quest_repository.dart';
import '../quests/quests_controller.dart';
import '../quests/signups_controller.dart';
import '../quests/widgets/quest_card.dart';

/// Адрес плиток карты. В релизе — Mapbox/MapTiler: `--dart-define=MAP_TILES_URL=...` (ключ не хранится в коде).
/// Плитки openstreetmap.org — только для разработки (правила OSM запрещают нагружать их из приложений).
const kMapTilesUrl = String.fromEnvironment('MAP_TILES_URL', defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
const kMapAttribution = String.fromEnvironment('MAP_ATTRIBUTION', defaultValue: '© OpenStreetMap');

enum _View { map, list }

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();
  _View _view = _View.map;
  LatLng? _me;
  String? _selectedId;
  late LocationPermission _perm;

  @override
  void initState() {
    super.initState();
    final loc = ref.read(locationServiceProvider);
    _perm = loc.permission;
    if (_perm == LocationPermission.granted) loc.current().then((p) => mounted ? setState(() => _me = p) : null);
  }

  Future<void> _allowLocation() async {
    final loc = ref.read(locationServiceProvider);
    final p = await loc.request();
    final me = await loc.current();
    if (!mounted) return;
    setState(() {
      _perm = p;
      _me = me;
    });
    if (me != null) _map.move(ll.LatLng(me.lat, me.lng), 14);
  }

  void _openQuest(Quest q) => context.push('/quest/${q.id}');

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final filter = ref.watch(questFilterProvider);
    final quests = ref.watch(questsProvider);
    final m = ref.watch(membershipProvider);
    ref.watch(mySignupsProvider); // статусы «Вы записаны» на карточках

    return Scaffold(
      appBar: AppBar(
        title: Text(l.quests),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: Space.x3),
            child: SegmentedButton<_View>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: _View.map, icon: const Icon(Icons.map_outlined), tooltip: l.viewMap, label: Text(l.viewMap)),
                ButtonSegment(value: _View.list, icon: const Icon(Icons.view_list_rounded), tooltip: l.viewList, label: Text(l.viewList)),
              ],
              selected: {_view},
              onSelectionChanged: (v) {
                Haptics.play(HapticKind.light);
                setState(() => _view = v.first);
              },
            ),
          ),
        ],
      ),
      body: Column(children: [
        _FilterBar(filter: filter, hasLocation: _me != null),
        if (m?.status == MembershipStatus.pending)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
            color: c.lime,
            child: Text(l.pendingJoinNote(m!.orgName), style: context.text.bodyMedium),
          )
        else if (m == null || m.status == MembershipStatus.rejected)
          // Без организации квесты можно смотреть, но записаться нельзя — мягко подсказываем.
          Material(
            color: c.lime,
            child: InkWell(
              onTap: () => context.push(Routes.org),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.x4, vertical: Space.x2),
                child: Row(children: [
                  Expanded(child: Text(l.noOrgMapNote, style: context.text.bodyMedium)),
                  Text(l.choose, style: context.text.labelLarge?.copyWith(color: c.primaryStrong)),
                  Icon(Icons.chevron_right_rounded, color: c.primaryStrong),
                ]),
              ),
            ),
          ),
        Expanded(
          child: quests.when(
            loading: () => ListView(
              padding: const EdgeInsets.all(Space.screen),
              children: const [SkeletonListTile(), SkeletonListTile(), SkeletonListTile()],
            ),
            error: (e, _) => ErrorState(
              title: l.errorNetworkTitle,
              body: l.errorNetworkBody,
              retryLabel: l.retry,
              onRetry: () => ref.invalidate(questsProvider),
            ),
            data: (all) {
              final rows = filterQuests(all, filter, me: _me, now: DateTime.now());
              if (rows.isEmpty) {
                return EmptyState(
                  title: l.noQuestsTitle,
                  body: l.noQuestsBody,
                  actionLabel: filter.isEmpty ? null : l.resetFilters,
                  onAction: () => ref.read(questFilterProvider.notifier).reset(),
                );
              }
              return AnimatedSwitcher(
                duration: Motion.of(context, Motion.base),
                child: _view == _View.list ? _list(rows) : _mapView(rows),
              );
            },
          ),
        ),
      ]),
    );
  }

  Widget _list(List<({Quest quest, double? km})> rows) => ListView.separated(
        key: const ValueKey('list'),
        padding: const EdgeInsets.all(Space.screen),
        itemCount: rows.length + 1,
        separatorBuilder: (_, __) => const SizedBox(height: Space.x3),
        itemBuilder: (context, i) => i == 0
            ? Text(context.l.questsCount(rows.length), style: context.text.labelSmall?.copyWith(color: context.colors.text2))
            : QuestCard(
                quest: rows[i - 1].quest,
                km: rows[i - 1].km,
                statusLabel: signupLabel(context.l, ref.read(mySignupsProvider.notifier).forQuest(rows[i - 1].quest.id)),
                onTap: () => _openQuest(rows[i - 1].quest),
              ),
      );

  Widget _mapView(List<({Quest quest, double? km})> rows) {
    final l = context.l;
    final c = context.colors;
    final sel = rows.where((r) => r.quest.id == _selectedId).firstOrNull;
    final center = _me ?? kCities.first.center;
    return Stack(key: const ValueKey('map'), children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: ll.LatLng(center.lat, center.lng),
          initialZoom: 12.5,
          minZoom: 4,
          onTap: (_, __) => setState(() => _selectedId = null),
        ),
        children: [
          TileLayer(urlTemplate: kMapTilesUrl, userAgentPackageName: 'kz.tazaniyet.app'),
          MarkerLayer(markers: [
            for (final r in rows)
              Marker(
                point: ll.LatLng(r.quest.location.lat, r.quest.location.lng),
                width: Hit.min,
                height: Hit.min,
                child: Semantics(
                  button: true,
                  label: '${r.quest.title}, ${questWhen(context, r.quest.startsAt)}',
                  child: GestureDetector(
                    onTap: () {
                      Haptics.play(HapticKind.light);
                      setState(() => _selectedId = r.quest.id);
                    },
                    child: Center(
                      child: AnimatedScale(
                        scale: r.quest.id == _selectedId ? 1.25 : 1,
                        duration: Motion.of(context, Motion.fast),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: r.quest.id == _selectedId ? c.primary : c.text,
                            border: Border.all(color: Colors.white, width: 3),
                            boxShadow: Shadows.e2,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${r.quest.difficulty.index + 1}',
                            style: context.text.labelLarge?.copyWith(color: r.quest.id == _selectedId ? c.onPrimary : c.bg),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (_me != null)
              Marker(
                point: ll.LatLng(_me!.lat, _me!.lng),
                width: 22,
                height: 22,
                child: Semantics(
                  label: l.myLocation,
                  child: Container(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary, border: Border.all(color: Colors.white, width: 4)),
                  ),
                ),
              ),
          ]),
          const SimpleAttributionWidget(source: Text(kMapAttribution)),
        ],
      ),
      // Кнопки масштаба и «моё место» — 48×48
      Positioned(
        right: Space.x3,
        top: Space.x3,
        child: Column(children: [
          _RoundBtn(icon: Icons.add_rounded, label: l.zoomIn, onTap: () => _map.move(_map.camera.center, _map.camera.zoom + 1)),
          const SizedBox(height: Space.x2),
          _RoundBtn(icon: Icons.remove_rounded, label: l.zoomOut, onTap: () => _map.move(_map.camera.center, _map.camera.zoom - 1)),
          const SizedBox(height: Space.x2),
          _RoundBtn(
            icon: Icons.my_location_rounded,
            label: l.myLocation,
            onTap: _me == null ? _allowLocation : () => _map.move(ll.LatLng(_me!.lat, _me!.lng), 14),
          ),
        ]),
      ),
      // Объяснение перед запросом геолокации
      if (_perm == LocationPermission.notAsked)
        Positioned(
          left: Space.x3,
          right: 72,
          top: Space.x3,
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l.locMapTitle, style: context.text.titleMedium),
              const SizedBox(height: Space.x1),
              Text(l.locMapBody, style: context.text.bodyMedium?.copyWith(color: c.text2)),
              const SizedBox(height: Space.x3),
              Row(children: [
                Expanded(child: AppButton(label: l.locAllow, onPressed: _allowLocation)),
                const SizedBox(width: Space.x2),
                Expanded(
                  child: AppButton(
                    label: l.notNow,
                    kind: AppButtonKind.ghost,
                    onPressed: () => setState(() => _perm = LocationPermission.denied),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      // Карточка выбранного квеста
      if (sel != null)
        Positioned(
          left: Space.x3,
          right: Space.x3,
          bottom: Space.x3,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            QuestCard(
              quest: sel.quest,
              km: sel.km,
              statusLabel: signupLabel(l, ref.read(mySignupsProvider.notifier).forQuest(sel.quest.id)),
              onTap: () => _openQuest(sel.quest),
            ),
            const SizedBox(height: Space.x2),
            AppButton(label: l.details, onPressed: () => _openQuest(sel.quest)),
          ]),
        ),
    ]);
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: context.colors.surface,
        shape: const CircleBorder(),
        elevation: 2,
        child: IconButton(icon: Icon(icon), tooltip: label, onPressed: onTap, constraints: const BoxConstraints.tightFor(width: Hit.min, height: Hit.min)),
      );
}

/// Фильтры: дата, сложность, «до 3 км».
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter, required this.hasLocation});
  final QuestFilter filter;
  final bool hasLocation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final ctl = ref.read(questFilterProvider.notifier);
    void tap(QuestFilter f) {
      Haptics.play(HapticKind.light);
      ctl.set(f);
    }

    Widget chip(String label, bool on, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: Space.x2),
          child: FilterChip(label: Text(label), selected: on, onSelected: (_) => onTap()),
        );

    Set<Difficulty> toggle(Difficulty d) =>
        filter.difficulties.contains(d) ? ({...filter.difficulties}..remove(d)) : {...filter.difficulties, d};

    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.screen, vertical: Space.x2),
        children: [
          chip(l.fToday, filter.date == DateScope.today,
              () => tap(filter.copyWith(date: filter.date == DateScope.today ? DateScope.any : DateScope.today))),
          chip(l.fWeek, filter.date == DateScope.week,
              () => tap(filter.copyWith(date: filter.date == DateScope.week ? DateScope.any : DateScope.week))),
          chip(l.fEasy, filter.difficulties.contains(Difficulty.easy), () => tap(filter.copyWith(difficulties: toggle(Difficulty.easy)))),
          chip(l.fMedium, filter.difficulties.contains(Difficulty.medium), () => tap(filter.copyWith(difficulties: toggle(Difficulty.medium)))),
          chip(l.fHard, filter.difficulties.contains(Difficulty.hard), () => tap(filter.copyWith(difficulties: toggle(Difficulty.hard)))),
          if (hasLocation) chip(l.fNear, filter.nearOnly, () => tap(filter.copyWith(nearOnly: !filter.nearOnly))),
        ],
      ),
    );
  }
}
