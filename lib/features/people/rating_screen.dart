import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/l10n_x.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/skeleton.dart';
import '../../core/widgets/state_views.dart';
import '../shift/widgets/hours_format.dart';
import 'data/people_repository.dart';
import 'people_controller.dart';
import 'people_widgets.dart';

/// Полный рейтинг месяца: организация или город.
class RatingScreen extends ConsumerWidget {
  const RatingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final scope = ref.watch(ratingScopeProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.ratingTitle)),
      body: ListView(padding: const EdgeInsets.fromLTRB(Space.screen, 0, Space.screen, Space.x8), children: [
        SegmentedButton<RatingScope>(
          showSelectedIcon: false,
          segments: [ButtonSegment(value: RatingScope.org, label: Text(l.ratingOrg)), ButtonSegment(value: RatingScope.city, label: Text(l.ratingCity))],
          selected: {scope},
          onSelectionChanged: (v) => ref.read(ratingScopeProvider.notifier).state = v.first,
        ),
        const SizedBox(height: Space.x2),
        Text(l.ratingNote, style: context.text.bodySmall?.copyWith(color: context.colors.text2)),
        const SizedBox(height: Space.x3),
        ref.watch(ratingProvider).when(
              loading: () => const Column(children: [SkeletonListTile(), SkeletonListTile()]),
              error: (_, __) => ErrorState(title: l.errorNetworkTitle, body: l.errorNetworkBody, retryLabel: l.retry, onRetry: () => ref.invalidate(allPeopleProvider)),
              data: (rows) => rows == null
                  ? Text(l.ratingEmpty)
                  : Column(children: [
                      for (final r in rows) RatingTile(row: r, formatted: formatHours(context, r.monthHours), onTap: () => context.push('/people/${r.id}')),
                    ]),
            ),
      ]),
    );
  }
}
