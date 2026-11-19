import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/geo.dart';
import '../../../core/l10n_x.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/ui/haptics.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/screens/auth_widgets.dart';
import '../data/org_repository.dart';
import '../org_controller.dart';

String orgTypeLabel(AppLocalizations l, OrgType t) => switch (t) {
      OrgType.ecology => l.typeEcology,
      OrgType.animals => l.typeAnimals,
      OrgType.social => l.typeSocial,
      OrgType.greening => l.typeGreening,
      OrgType.youth => l.typeYouth,
      OrgType.sports => l.typeSports,
    };

/// Выбор организации: объяснение перед запросом геолокации, Рядом / Мой город / Все, поиск, код приглашения.
class OrgPickerScreen extends ConsumerStatefulWidget {
  const OrgPickerScreen({super.key, this.inviteCode});

  /// Код из ссылки-приглашения tazaniyet.kz/join/<код> — сразу открываем ввод кода.
  final String? inviteCode;

  @override
  ConsumerState<OrgPickerScreen> createState() => _OrgPickerScreenState();
}

class _OrgPickerScreenState extends ConsumerState<OrgPickerScreen> {
  List<Organization>? _orgs;
  Object? _loadError;
  LatLng? _me;
  late LocationPermission _perm;
  OrgScope _scope = OrgScope.city;
  String _cityId = 'astana';
  String _query = '';
  String? _joiningId;

  @override
  void initState() {
    super.initState();
    _perm = ref.read(locationServiceProvider).permission;
    _load();
    if (widget.inviteCode != null) WidgetsBinding.instance.addPostFrameCallback((_) => _enterCode());
  }

  Future<void> _load() async {
    setState(() {
      _orgs = null;
      _loadError = null;
    });
    try {
      final list = await ref.read(orgRepositoryProvider).list();
      if (mounted) setState(() => _orgs = list);
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _allowLocation() async {
    final loc = ref.read(locationServiceProvider);
    final p = await loc.request();
    final me = await loc.current();
    if (!mounted) return;
    setState(() {
      _perm = p;
      _me = me;
      if (me != null) {
        _scope = OrgScope.nearby;
        // Город — ближайший к пользователю.
        _cityId = (kCities.toList()..sort((a, b) => distanceKm(me, a.center).compareTo(distanceKm(me, b.center)))).first.id;
      }
    });
  }

  Future<void> _pickCity() async {
    final lang = Localizations.localeOf(context).languageCode;
    final id = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final c in kCities)
            ListTile(
              minTileHeight: Hit.min,
              title: Text(c.name(lang)),
              trailing: c.id == _cityId ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(context, c.id),
            ),
        ]),
      ),
    );
    if (id != null) {
      setState(() {
        _cityId = id;
        _scope = OrgScope.city;
        if (_perm == LocationPermission.notAsked) _perm = LocationPermission.denied;
      });
    }
  }

  Future<void> _join(Organization org) async {
    Haptics.play(HapticKind.medium);
    setState(() => _joiningId = org.id);
    try {
      await ref.read(membershipProvider.notifier).request(org);
      if (mounted) context.pushReplacement(Routes.orgPending);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l.errorNetworkBody)));
      }
    } finally {
      if (mounted) setState(() => _joiningId = null);
    }
  }

  Future<void> _enterCode() async {
    final org = await showModalBottomSheet<Organization>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _InviteCodeSheet(initial: widget.inviteCode),
    );
    if (org != null) await _join(org);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final lang = Localizations.localeOf(context).languageCode;
    final city = kCities.firstWhere((x) => x.id == _cityId);

    Widget body;
    if (_loadError != null) {
      body = ErrorState(title: l.errorNetworkTitle, body: l.errorNetworkBody, retryLabel: l.retry, onRetry: _load);
    } else if (_orgs == null) {
      body = ListView(
        padding: const EdgeInsets.symmetric(horizontal: Space.screen),
        children: const [SkeletonListTile(), SkeletonListTile(), SkeletonListTile(), SkeletonListTile()],
      );
    } else {
      final rows = filterOrgs(_orgs!, scope: _scope, cityId: _cityId, me: _me, query: _query);
      body = rows.isEmpty
          ? (_query.isNotEmpty
              ? EmptyState(title: l.noResults(_query), body: l.noNearbyBody)
              : EmptyState(
                  title: l.noNearby,
                  body: l.noNearbyBody,
                  actionLabel: l.segCity,
                  onAction: () => setState(() => _scope = OrgScope.city),
                ))
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.x6),
              itemCount: rows.length,
              separatorBuilder: (_, __) => const SizedBox(height: Space.x3),
              itemBuilder: (context, i) {
                final r = rows[i];
                final o = r.org;
                final busy = _joiningId == o.id;
                return AppCard(
                  child: Row(children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: c.lime,
                      child: Text(o.name.characters.first, style: context.text.titleMedium?.copyWith(color: c.onPrimary)),
                    ),
                    const SizedBox(width: Space.x3),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(child: Text(o.name, style: context.text.titleMedium, overflow: TextOverflow.ellipsis)),
                          if (o.verified) ...[
                            const SizedBox(width: Space.x1),
                            Icon(Icons.verified_rounded, size: 16, color: c.primaryStrong, semanticLabel: l.verified),
                          ],
                        ]),
                        Text(orgTypeLabel(l, o.type), style: context.text.bodyMedium?.copyWith(color: c.text2)),
                        Text(
                          [
                            if (r.km != null) l.kmAway(formatKm(r.km!, lang)),
                            kCities.firstWhere((x) => x.id == o.cityId).name(lang),
                            l.members(o.members),
                          ].join(' · '),
                          style: context.text.labelSmall?.copyWith(color: c.text2),
                        ),
                      ]),
                    ),
                    const SizedBox(width: Space.x2),
                    AppButton(
                      label: l.join,
                      expand: false,
                      loading: busy,
                      onPressed: _joiningId != null ? null : () => _join(o),
                    ),
                  ]),
                );
              },
            );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l.orgTitle)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.x3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(l.orgBody, style: context.text.bodyLarge?.copyWith(color: c.text2)),
            const SizedBox(height: Space.x3),
            // Объяснение до системного запроса — разрешение просим только по нажатию.
            if (_perm == LocationPermission.notAsked)
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.near_me_rounded, color: c.primaryStrong),
                    const SizedBox(width: Space.x2),
                    Expanded(child: Text(l.locWhyTitle, style: context.text.titleMedium)),
                  ]),
                  const SizedBox(height: Space.x2),
                  Text(l.locWhyBody, style: context.text.bodyMedium?.copyWith(color: c.text2)),
                  const SizedBox(height: Space.x3),
                  Row(children: [
                    Expanded(child: AppButton(label: l.locAllow, onPressed: _allowLocation)),
                    const SizedBox(width: Space.x2),
                    Expanded(child: AppButton(label: l.locManual, kind: AppButtonKind.secondary, onPressed: _pickCity)),
                  ]),
                ]),
              )
            else ...[
              if (_perm == LocationPermission.denied)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.x2),
                  child: Text(l.locDenied, style: context.text.labelSmall?.copyWith(color: c.text2)),
                ),
              SegmentedButton<OrgScope>(
                segments: [
                  if (_me != null) ButtonSegment(value: OrgScope.nearby, label: Text(l.segNearby)),
                  ButtonSegment(value: OrgScope.city, label: Text(city.name(lang))),
                  ButtonSegment(value: OrgScope.all, label: Text(l.segAll)),
                ],
                selected: {_scope},
                onSelectionChanged: (v) => setState(() => _scope = v.first),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickCity,
                  icon: const Icon(Icons.location_city_rounded, size: 18),
                  label: Text('${l.cityLabel}: ${city.name(lang)}'),
                ),
              ),
            ],
            const SizedBox(height: Space.x2),
            TextField(
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(hintText: l.orgSearch, prefixIcon: const Icon(Icons.search_rounded)),
            ),
          ]),
        ),
        Expanded(child: AnimatedSwitcher(duration: Motion.of(context, Motion.base), child: KeyedSubtree(key: ValueKey('$_scope$_cityId${_orgs == null}'), child: body))),
        SafeArea(
          top: false,
          child: TextButton.icon(
            onPressed: _enterCode,
            style: TextButton.styleFrom(minimumSize: const Size(Hit.min, Hit.min)),
            icon: const Icon(Icons.vpn_key_outlined),
            label: Text(l.haveCode),
          ),
        ),
      ]),
    );
  }
}

class _InviteCodeSheet extends ConsumerStatefulWidget {
  const _InviteCodeSheet({this.initial});
  final String? initial;

  @override
  ConsumerState<_InviteCodeSheet> createState() => _InviteCodeSheetState();
}

class _InviteCodeSheetState extends ConsumerState<_InviteCodeSheet> {
  late final _code = TextEditingController(text: widget.initial);
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final org = await ref.read(orgRepositoryProvider).findByInviteCode(_code.text);
      if (mounted) Navigator.pop(context, org);
    } on OrgFailure catch (e) {
      if (mounted) setState(() => _error = e.reason == 'code_not_found' ? context.l.errCode : context.l.errorNetworkBody);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, MediaQuery.viewInsetsOf(context).bottom + Space.x6),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(l.codeTitle, style: context.text.titleLarge),
        const SizedBox(height: Space.x1),
        Text(l.codeHint, style: context.text.bodyMedium?.copyWith(color: context.colors.text2)),
        const SizedBox(height: Space.x4),
        TextField(
          controller: _code,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _check(),
          decoration: InputDecoration(labelText: l.codeTitle, hintText: 'TAZA2026'),
        ),
        InlineError(_error),
        const SizedBox(height: Space.x4),
        AppButton(label: l.join, loading: _loading, onPressed: _code.text.trim().length < 4 ? null : _check),
      ]),
    );
  }
}
