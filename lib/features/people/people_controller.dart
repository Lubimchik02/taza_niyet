import '../../core/backend/backend.dart';
import '../../core/backend/supabase_data.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/notifications.dart';
import 'data/people_repository.dart';

// Сервер, если при сборке заданы SUPABASE_URL и SUPABASE_ANON_KEY; иначе демо.
final peopleRepositoryProvider = Provider<PeopleRepository>((ref) => Backend.enabled ? SupabasePeopleRepository() : FakePeopleRepository());

@immutable
class FriendsState {
  const FriendsState({this.friends = const {}, this.outgoing = const {}, this.incoming = const {}});
  final Set<String> friends, outgoing, incoming;

  FriendsState copyWith({Set<String>? friends, Set<String>? outgoing, Set<String>? incoming}) =>
      FriendsState(friends: friends ?? this.friends, outgoing: outgoing ?? this.outgoing, incoming: incoming ?? this.incoming);
}

/// Друзья и заявки. Дружба — только взаимная: личные чаты и часы «для друзей» открываются после согласия.
class FriendsController extends Notifier<FriendsState> {
  @override
  FriendsState build() => Backend.enabled ? const FriendsState() : const FriendsState(friends: {'tk', 'ds'}, incoming: {'am'}); // демо

  PeopleRepository get _repo => ref.read(peopleRepositoryProvider);

  /// Отправить заявку. Возвращает true, если человек согласился (демо — через 3 с).
  Future<bool> request(String id) async {
    await _repo.sendRequest(id);
    state = state.copyWith(outgoing: {...state.outgoing, id});
    final ok = await _repo.awaitAnswer(id);
    if (!state.outgoing.contains(id)) return false; // заявку отозвали
    state = state.copyWith(outgoing: {...state.outgoing}..remove(id), friends: ok ? {...state.friends, id} : state.friends);
    if (ok) {
      final name = _repo.cached(id)?.name ?? '';
      ref.read(inboxProvider.notifier).add(kind: NotifKind.friend, route: '/people/$id', args: {'name': name});
    }
    return ok;
  }

  void cancel(String id) => state = state.copyWith(outgoing: {...state.outgoing}..remove(id));

  void accept(String id) {
    state = state.copyWith(incoming: {...state.incoming}..remove(id), friends: {...state.friends, id});
    _repo.respond(id, accept: true);
  }

  void decline(String id) {
    state = state.copyWith(incoming: {...state.incoming}..remove(id));
    _repo.respond(id, accept: false);
  }

  void remove(String id) {
    state = state.copyWith(friends: {...state.friends}..remove(id));
    _repo.remove(id);
  }

  /// Подтянуть с сервера (при запуске и по уведомлению «заявка в друзья»).
  Future<void> sync() async {
    final s = await _repo.loadFriends();
    if (s != null) state = FriendsState(friends: s.friends, outgoing: s.outgoing, incoming: s.incoming);
  }
}

final friendsProvider = NotifierProvider<FriendsController, FriendsState>(FriendsController.new);

final allPeopleProvider = FutureProvider<List<Person>>((ref) => ref.read(peopleRepositoryProvider).all());

final personProvider = FutureProvider.autoDispose.family<Person?, String>((ref, id) => ref.read(peopleRepositoryProvider).byId(id));

final peopleSearchProvider = FutureProvider.autoDispose.family<List<Person>, String>((ref, q) async {
  // Небольшая пауза: не отправляем запрос на каждую букву.
  await Future<void>.delayed(const Duration(milliseconds: 250));
  return ref.read(peopleRepositoryProvider).search(q);
});

/// Имена друзей для списка чатов (личные — только с друзьями).
final friendPeopleProvider = Provider<List<Person>>((ref) {
  final repo = ref.read(peopleRepositoryProvider);
  return ref.watch(friendsProvider).friends.map(repo.cached).whereType<Person>().toList();
});
