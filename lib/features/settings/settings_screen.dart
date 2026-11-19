import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/app_config.dart';
import '../../core/l10n_x.dart';
import '../../core/net/connectivity.dart';
import '../../core/router/app_router.dart';
import '../../core/settings/settings_controller.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/ui/haptics.dart';
import '../../core/widgets/app_button.dart';
import '../auth/auth_controller.dart';
import '../chats/chats_controller.dart';
import '../people/people_controller.dart';
import '../profile/data/portfolio.dart';
import '../profile/profile_controller.dart';
import '../notifications/notifications.dart';
import 'export.dart';
import 'settings_prefs.dart';

enum SettingsSection { account, security, notifications, privacy, appearance, a11y, data, delete, about, dev }

/// Настройки: 9 разделов. Каждый — отдельный экран `/settings/<раздел>`.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final items = [
      (SettingsSection.account, Icons.person_outline_rounded, l.secAccount),
      (SettingsSection.security, Icons.lock_outline_rounded, l.secSecurity),
      (SettingsSection.notifications, Icons.notifications_none_rounded, l.secNotifications),
      (SettingsSection.privacy, Icons.visibility_outlined, l.secPrivacy),
      (SettingsSection.appearance, Icons.translate_rounded, l.secAppearance),
      (SettingsSection.a11y, Icons.accessibility_new_rounded, l.secA11y),
      (SettingsSection.data, Icons.download_rounded, l.secData),
      (SettingsSection.about, Icons.help_outline_rounded, l.secAbout),
      (SettingsSection.delete, Icons.delete_outline_rounded, l.secDelete),
      // Только в отладочной сборке: имитация сети, обновлений, флагов и ссылок.
      if (kDebugMode) (SettingsSection.dev, Icons.science_outlined, l.devPanel),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(children: [
        for (final (s, icon, title) in items)
          ListTile(
            leading: Icon(icon, color: s == SettingsSection.delete ? c.danger : c.primaryStrong),
            title: Text(title, style: s == SettingsSection.delete ? TextStyle(color: c.danger) : null),
            trailing: const Icon(Icons.chevron_right_rounded),
            minVerticalPadding: Space.x3,
            onTap: () => context.push('/settings/${s.name}'),
          ),
      ]),
    );
  }
}

class SettingsSectionScreen extends ConsumerWidget {
  const SettingsSectionScreen({super.key, required this.section});
  final SettingsSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final (title, body) = switch (section) {
      SettingsSection.account => (l.secAccount, const _Account()),
      SettingsSection.security => (l.secSecurity, const _Security()),
      SettingsSection.notifications => (l.secNotifications, const _Notifications()),
      SettingsSection.privacy => (l.secPrivacy, const _Privacy()),
      SettingsSection.appearance => (l.secAppearance, const _Appearance()),
      SettingsSection.a11y => (l.secA11y, const _A11y()),
      SettingsSection.data => (l.secData, const _Data()),
      SettingsSection.delete => (l.secDelete, const _Delete()),
      SettingsSection.about => (l.secAbout, const _About()),
      SettingsSection.dev => (l.devPanel, const _Dev()),
    };
    return Scaffold(appBar: AppBar(title: Text(title)), body: body);
  }
}

Widget _header(BuildContext context, String t) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.screen, Space.x4, Space.screen, Space.x1),
      child: Semantics(header: true, child: Text(t, style: context.text.titleSmall?.copyWith(color: context.colors.primaryStrong))),
    );

Widget _note(BuildContext context, String t) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.screen, Space.x2, Space.screen, Space.x2),
      child: Text(t, style: context.text.bodySmall?.copyWith(color: context.colors.text2)),
    );

class _Toggle extends ConsumerWidget {
  const _Toggle(this.k, this.title, [this.subtitle]);
  final String k, title;
  final String? subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) => SwitchListTile(
        value: ref.watch(toggleProvider(k)),
        onChanged: (v) {
          Haptics.play(HapticKind.light);
          ref.read(toggleProvider(k).notifier).set(v);
        },
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
      );
}

String _mask(String? v) {
  if (v == null || v.isEmpty) return '—';
  if (v.contains('@')) {
    final i = v.indexOf('@');
    return '${v.substring(0, i.clamp(0, 2))}•••${v.substring(i)}';
  }
  return v.length > 4 ? '${v.substring(0, v.length - 4).replaceAll(RegExp(r'\d'), '•')}${v.substring(v.length - 4)}' : v;
}

class _Account extends ConsumerWidget {
  const _Account();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final u = ref.watch(sessionProvider);
    return ListView(children: [
      ListTile(
        leading: const Icon(Icons.badge_outlined),
        title: Text(u?.name ?? ''),
        subtitle: Text(l.nameEdit),
        trailing: const Icon(Icons.edit_outlined),
        onTap: () async {
          final ctrl = TextEditingController(text: u?.name);
          final name = await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(l.nameEdit),
              content: TextField(controller: ctrl, autofocus: true, textCapitalization: TextCapitalization.words, maxLength: 40, decoration: InputDecoration(labelText: l.nameLabel)),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l.keep)),
                TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(l.done)),
              ],
            ),
          );
          if (name != null && RegExp(r'\p{L}.*\p{L}', unicode: true).hasMatch(name)) await ref.read(sessionProvider.notifier).rename(name);
        },
      ),
      ListTile(leading: const Icon(Icons.cake_outlined), title: Text('${u?.birthYear ?? '—'}'), subtitle: Text(l.birthYearLocked)),
      ListTile(leading: const Icon(Icons.alternate_email_rounded), title: Text(l.signInWith), subtitle: Text([_mask(u?.email), _mask(u?.phone)].where((x) => x != '—').join(' · '))),
      const Divider(),
      ListTile(
        leading: const Icon(Icons.logout_rounded),
        title: Text(l.signOutAction),
        onTap: () => ref.read(sessionProvider.notifier).signOut(),
      ),
    ]);
  }
}

class _Security extends ConsumerWidget {
  const _Security();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final c = context.colors;
    final sessions = ref.watch(sessionsProvider);
    final messenger = ScaffoldMessenger.of(context);
    return ListView(children: [
      SwitchListTile(
        value: ref.watch(twoFactorProvider),
        title: Text(l.twoFa),
        subtitle: Text(l.twoFaSub),
        onChanged: (v) async {
          ref.read(twoFactorProvider.notifier).state = v;
          if (!v) return;
          // Резервные коды показываем один раз — сразу после включения.
          final codes = [for (var i = 0; i < 8; i++) (100000 + (DateTime.now().microsecond * (i + 7)) % 900000).toString()];
          await showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (ctx) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Space.x6, 0, Space.x6, Space.x4),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.backupCodesT, style: ctx.text.titleLarge),
                  const SizedBox(height: Space.x2),
                  Text(l.backupCodesB, style: ctx.text.bodyMedium?.copyWith(color: ctx.colors.text2)),
                  const SizedBox(height: Space.x3),
                  Wrap(spacing: Space.x4, runSpacing: Space.x2, children: [for (final x in codes) Text(x, style: ctx.text.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]))]),
                  const SizedBox(height: Space.x4),
                  AppButton(label: l.copyAction, kind: AppButtonKind.secondary, onPressed: () {
                    Clipboard.setData(ClipboardData(text: codes.join('\n')));
                    Navigator.pop(ctx);
                    messenger.showSnackBar(SnackBar(content: Text(l.copied)));
                  }),
                ]),
              ),
            ),
          );
        },
      ),
      ListTile(
        leading: const Icon(Icons.key_rounded),
        title: Text(l.passkeys),
        subtitle: Text('${ref.watch(passkeysProvider)}'),
        trailing: TextButton(
          onPressed: () async {
            ref.read(passkeysProvider.notifier).state++;
            messenger.showSnackBar(SnackBar(content: Text(l.passkeyAdded)));
          },
          child: Text(l.passkeyAdd),
        ),
      ),
      _header(context, l.sessionsT),
      for (final s in sessions)
        ListTile(
          leading: Icon(s.device.contains('iPad') ? Icons.tablet_mac_rounded : Icons.smartphone_rounded),
          title: Text(s.device),
          subtitle: Text(s.current ? '${s.place} · ${l.thisDevice}' : '${s.place} · ${s.lastActive.day.toString().padLeft(2, '0')}.${s.lastActive.month.toString().padLeft(2, '0')}'),
          trailing: s.current ? Icon(Icons.check_circle_rounded, color: c.primaryStrong) : TextButton(onPressed: () => ref.read(sessionsProvider.notifier).end(s.id), child: Text(l.endSession)),
        ),
      if (sessions.length > 1)
        Padding(
          padding: const EdgeInsets.all(Space.screen),
          child: AppButton(
            label: l.endOthers,
            kind: AppButtonKind.danger,
            onPressed: () async {
              await ref.read(sessionsProvider.notifier).endOthers();
              messenger.showSnackBar(SnackBar(content: Text(l.sessionsEnded)));
            },
          ),
        ),
    ]);
  }
}

class _Notifications extends StatelessWidget {
  const _Notifications();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return ListView(children: [
      _Toggle(Toggles.nShifts, l.nShifts, l.nShiftsSub),
      _Toggle(Toggles.nHours, l.nHours),
      _Toggle(Toggles.nChats, l.nChats),
      _Toggle(Toggles.nFriends, l.nFriends),
      _Toggle(Toggles.nQuests, l.nQuests),
      _Toggle(Toggles.nNews, l.nNews),
      const Divider(),
      _Toggle(Toggles.quiet, l.quietHours, l.quietHoursSub),
      _note(context, l.pushLater),
    ]);
  }
}

class _Privacy extends ConsumerWidget {
  const _Privacy();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final minor = ref.watch(isMinorProvider);
    final vis = ref.watch(hoursVisibilityProvider);
    final who = ref.watch(whoCanAddProvider);
    final blocked = ref.watch(chatStoreProvider).blocked;
    String visLabel(HoursVisibility v) => switch (v) { HoursVisibility.everyone => l.visAll, HoursVisibility.friends => l.visFriends, HoursVisibility.onlyMe => l.visMe };
    String whoLabel(WhoCanAdd v) => switch (v) { WhoCanAdd.everyone => l.addEveryone, WhoCanAdd.myOrg => l.addMyOrg, WhoCanAdd.nobody => l.addNobody };
    return ListView(children: [
      _header(context, l.visibilityTitle),
      for (final v in HoursVisibility.values)
        RadioListTile<HoursVisibility>(
          value: v,
          groupValue: vis,
          title: Text(visLabel(v)),
          onChanged: minor && v == HoursVisibility.everyone ? null : (x) => ref.read(hoursVisibilityProvider.notifier).set(x!),
        ),
      _header(context, l.whoCanAdd),
      for (final v in WhoCanAdd.values)
        RadioListTile<WhoCanAdd>(value: v, groupValue: who, title: Text(whoLabel(v)), onChanged: (x) => ref.read(whoCanAddProvider.notifier).set(x!)),
      const Divider(),
      _Toggle(Toggles.showInSearch, l.showInSearch),
      _Toggle(Toggles.showInRating, l.showInRating),
      if (minor) _note(context, l.minorPrivacyNote),
      _header(context, l.blockedUsers),
      if (blocked.isEmpty) _note(context, l.noBlocked),
      for (final id in blocked)
        ListTile(
          title: Text(ref.read(peopleRepositoryProvider).cached(id)?.name ?? id),
          trailing: TextButton(onPressed: () => ref.read(chatStoreProvider.notifier).setBlocked(id, false), child: Text(l.unblockAction)),
        ),
    ]);
  }
}

class _Appearance extends ConsumerWidget {
  const _Appearance();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final s = ref.watch(settingsProvider);
    final ctrl = ref.read(settingsProvider.notifier);
    return ListView(children: [
      _header(context, l.language),
      for (final (code, label) in [(null, l.langSystem), ('kk', 'Қазақша'), ('ru', 'Русский'), ('en', 'English')])
        RadioListTile<String?>(value: code, groupValue: s.locale?.languageCode, title: Text(label), onChanged: (v) => ctrl.setLocale(v == null ? null : Locale(v))),
      _header(context, l.theme),
      for (final (m, label) in [(ThemeMode.system, l.themeSystem), (ThemeMode.light, l.themeLight), (ThemeMode.dark, l.themeDark)])
        RadioListTile<ThemeMode>(value: m, groupValue: s.themeMode, title: Text(label), onChanged: (v) => ctrl.setThemeMode(v!)),
    ]);
  }
}

class _A11y extends ConsumerWidget {
  const _A11y();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scale = ref.watch(textScaleProvider);
    return ListView(children: [
      _header(context, l.textSize),
      Slider(
        value: scale,
        min: 1,
        max: 1.5,
        divisions: 5,
        label: '${(scale * 100).round()}%',
        semanticFormatterCallback: (v) => '${(v * 100).round()}%',
        onChanged: (v) => ref.read(textScaleProvider.notifier).set(v),
      ),
      Padding(padding: const EdgeInsets.symmetric(horizontal: Space.screen), child: Text(l.textSizeSample, style: context.text.bodyLarge)),
      const SizedBox(height: Space.x3),
      _Toggle(Toggles.reduceMotion, l.reduceMotion, l.reduceMotionSub),
      _Toggle(Toggles.haptics, l.hapticsSetting),
    ]);
  }
}

class _Data extends ConsumerStatefulWidget {
  const _Data();
  @override
  ConsumerState<_Data> createState() => _DataState();
}

class _DataState extends ConsumerState<_Data> {
  String? _busy;

  Future<void> _share(String kind) async {
    final l = context.l;
    setState(() => _busy = kind);
    try {
      final bytes = kind == 'json'
          ? exportJson(ref)
          : await exportPortfolioPdf(ref, labels: {
              'title': l.portfolioTitle, 'hours': l.profileHours, 'shifts': l.profileShifts, 'date': l.pdfDate,
              'quest': l.pdfQuest, 'org': l.ratingOrg, 'verify': l.verifyTitle, 'issued': l.pdfIssued,
            });
      final name = kind == 'json' ? 'taza-niyet-data.json' : 'taza-niyet-portfolio.pdf';
      await Share.shareXFiles([XFile.fromData(bytes, name: name, mimeType: kind == 'json' ? 'application/json' : 'application/pdf')], fileNameOverrides: [name]);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.errUnknown)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    Widget tile(String kind, IconData icon, String title, String sub) => ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(sub),
          trailing: _busy == kind ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.ios_share_rounded),
          onTap: _busy == null ? () => _share(kind) : null,
        );
    return ListView(children: [
      tile('pdf', Icons.picture_as_pdf_outlined, l.exportPdf, l.exportPdfSub),
      tile('json', Icons.data_object_rounded, l.exportData, l.exportDataSub),
    ]);
  }
}

class _Delete extends ConsumerStatefulWidget {
  const _Delete();
  @override
  ConsumerState<_Delete> createState() => _DeleteState();
}

class _DeleteState extends ConsumerState<_Delete> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final ok = _ctrl.text.trim().toUpperCase() == l.deleteWord;
    Widget point(IconData i, String t) => Padding(
          padding: const EdgeInsets.only(bottom: Space.x3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(i, size: 20, color: c.text2), const SizedBox(width: Space.x3), Expanded(child: Text(t, style: context.text.bodyLarge))]),
        );
    return ListView(padding: const EdgeInsets.all(Space.screen), children: [
      Text(l.deleteT, style: context.text.headlineSmall),
      const SizedBox(height: Space.x4),
      point(Icons.delete_outline_rounded, l.deleteB1),
      point(Icons.verified_outlined, l.deleteB2),
      point(Icons.restore_rounded, l.deleteB3),
      Container(
        padding: const EdgeInsets.all(Space.x3),
        decoration: BoxDecoration(color: c.lime, borderRadius: BorderRadius.circular(Radii.sm)),
        child: Row(children: [
          Icon(Icons.picture_as_pdf_outlined, color: c.primaryStrong),
          const SizedBox(width: Space.x2),
          Expanded(child: Text(l.deleteTip)),
          TextButton(onPressed: () => context.push('/settings/data'), child: Text(l.exportPdf)),
        ]),
      ),
      const SizedBox(height: Space.x4),
      TextField(controller: _ctrl, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: l.deleteTypeHint, hintText: l.deleteWord)),
      const SizedBox(height: Space.x4),
      AppButton(
        label: l.deleteAction,
        kind: AppButtonKind.danger,
        loading: _busy,
        onPressed: !ok || _busy
            ? null
            : () async {
                setState(() => _busy = true);
                final messenger = ScaffoldMessenger.of(context);
                await ref.read(sessionProvider.notifier).deleteAccount();
                messenger.showSnackBar(SnackBar(content: Text(l.deleteDone)));
              },
      ),
    ]);
  }
}

class _About extends StatelessWidget {
  const _About();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    Future<void> open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return ListView(children: [
      ListTile(leading: const Icon(Icons.tag_rounded), title: Text(l.guideTitle), onTap: () => context.push(Routes.guide)),
      ListTile(leading: const Icon(Icons.mail_outline_rounded), title: Text(l.support), subtitle: const Text('help@tazaniyet.kz'), onTap: () => open('mailto:help@tazaniyet.kz?subject=Taza%20Niyet')),
      ListTile(leading: const Icon(Icons.star_outline_rounded), title: Text(l.rateApp), onTap: () => open('https://tazaniyet.kz/app')),
      const Divider(),
      ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: Text(l.privacyPolicy), onTap: () => open('https://tazaniyet.kz/privacy')),
      ListTile(leading: const Icon(Icons.description_outlined), title: Text(l.terms), onTap: () => open('https://tazaniyet.kz/terms')),
      ListTile(leading: const Icon(Icons.copyright_rounded), title: Text(l.licenses), onTap: () => showLicensePage(context: context, applicationName: 'Taza Niyet')),
      FutureBuilder(
        future: PackageInfo.fromPlatform(),
        builder: (_, snap) => _note(context, l.versionLabel(snap.hasData ? '${snap.data!.version} (${snap.data!.buildNumber})' : '…')),
      ),
    ]);
  }
}

class _Dev extends ConsumerStatefulWidget {
  const _Dev();
  @override
  ConsumerState<_Dev> createState() => _DevState();
}

class _DevState extends ConsumerState<_Dev> {
  final _link = TextEditingController(text: 'https://tazaniyet.kz/q/q10');

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final cfg = ref.watch(appConfigProvider);
    final ctrl = ref.read(appConfigProvider.notifier);
    final v = ref.watch(appVersionProvider).valueOrNull ?? '1.0.0';
    String bump(String x) {
      final p = x.split('.').map(int.parse).toList();
      return '${p[0]}.${p[1] + 1}.0';
    }

    return ListView(children: [
      SwitchListTile(title: Text(l.devOffline), value: !ref.watch(isOnlineProvider), onChanged: (x) => ref.read(devOfflineProvider.notifier).state = x),
      SwitchListTile(
        title: Text(l.devSoftUpdate),
        value: compareVersions(cfg.latestVersion, v) > 0,
        onChanged: (x) => ctrl.set(AppConfig(minVersion: cfg.minVersion, latestVersion: x ? bump(v) : v, flags: cfg.flags)),
      ),
      SwitchListTile(
        title: Text(l.devForceUpdate),
        value: compareVersions(cfg.minVersion, v) > 0,
        onChanged: (x) => ctrl.set(AppConfig(minVersion: x ? bump(v) : '1.0.0', latestVersion: x ? bump(v) : cfg.latestVersion, flags: cfg.flags)),
      ),
      _header(context, l.devFlags),
      for (final (f, label) in [(Flags.chats, l.flagChats), (Flags.rating, l.flagRating), (Flags.feed, l.flagFeed)])
        SwitchListTile(title: Text(label), value: cfg.flag(f), onChanged: (x) => ctrl.setFlag(f, x)),
      _header(context, l.devLink),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.screen),
        child: Row(children: [
          Expanded(child: TextField(controller: _link, keyboardType: TextInputType.url)),
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: () {
              final uri = Uri.tryParse(_link.text.trim());
              final ok = uri != null && (uri.host == 'tazaniyet.kz' || uri.host.isEmpty) && RegExp(r'^/(q|v|u|join)/[\w-]+$').hasMatch(uri.path);
              if (ok) {
                context.go(uri.path);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l.linkInvalid)));
              }
            },
          ),
        ]),
      ),
      ListTile(
        leading: const Icon(Icons.notifications_active_outlined),
        title: Text(l.devPush),
        onTap: () => ref.read(inboxProvider.notifier).add(kind: NotifKind.reminder, route: '/map', args: {'quest': 'Посадка деревьев в парке'}),
      ),
    ]);
  }
}
