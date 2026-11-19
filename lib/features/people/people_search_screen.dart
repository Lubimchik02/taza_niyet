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

/// Поиск волонтёров по имени. Часы видны сразу в списке — если человек их не скрыл.
class PeopleSearchScreen extends ConsumerStatefulWidget {
  const PeopleSearchScreen({super.key});

  @override
  ConsumerState<PeopleSearchScreen> createState() => _PeopleSearchScreenState();
}

class _PeopleSearchScreenState extends ConsumerState<PeopleSearchScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final c = context.colors;
    final q = _q.trim();
    final friends = ref.watch(friendsProvider);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(hintText: l.searchPeople, prefixIcon: const Icon(Icons.search_rounded)),
        ),
        actions: const [SizedBox(width: Space.x3)],
      ),
      body: q.length < 2
          ? EmptyState(title: l.searchPeople, body: l.searchMin)
          : ref.watch(peopleSearchProvider(q)).when(
                loading: () => ListView(padding: const EdgeInsets.all(Space.screen), children: const [SkeletonListTile(), SkeletonListTile()]),
                error: (_, __) => ErrorState(title: l.errorNetworkTitle, body: l.errorNetworkBody, retryLabel: l.retry, onRetry: () => ref.invalidate(peopleSearchProvider(q))),
                data: (list) => list.isEmpty
                    ? EmptyState(title: l.noResults(q), body: '')
                    : ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => Divider(height: 1, indent: 72, color: c.outline),
                        itemBuilder: (_, i) {
                          final p = list[i];
                          final isFriend = friends.friends.contains(p.id);
                          return ListTile(
                            minVerticalPadding: Space.x3,
                            leading: PersonAvatar(name: p.name),
                            title: Text(p.name),
                            subtitle: Text([p.orgName, if (isFriend) l.friendsLabel].join(' · ')),
                            trailing: Text(
                              canSeeHours(p, isFriend: isFriend) ? formatHours(context, p.hours) : l.hoursHidden,
                              style: context.text.titleSmall?.copyWith(color: canSeeHours(p, isFriend: isFriend) ? c.primaryStrong : c.text2),
                            ),
                            onTap: () => context.push('/people/${p.id}'),
                          );
                        },
                      ),
              ),
    );
  }
}
