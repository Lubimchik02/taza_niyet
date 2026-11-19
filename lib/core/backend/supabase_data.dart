import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/chats/data/chat_repository.dart';
import '../../features/org/data/org_repository.dart';
import '../../features/people/data/people_repository.dart';
import '../../features/profile/data/portfolio.dart';
import '../../features/quests/data/quest_repository.dart';
import '../../features/quests/data/signup_repository.dart';
import '../../features/shift/data/shift_repository.dart';
import '../geo.dart';
import 'backend.dart';

SupabaseClient get _db => Backend.client;
String get _me => _db.auth.currentUser?.id ?? '';
T _enum<T extends Enum>(List<T> values, Object? v, T fallback) => values.where((e) => e.name == v).firstOrNull ?? fallback;

/// Названия ошибок сервера (raise exception '…') → ошибки приложения.
Never _rethrow(Object e) {
  final msg = e is PostgrestException ? e.message : '$e';
  if (msg.contains('time_conflict')) throw const SignupFailure(SignupFailureKind.timeConflict);
  if (msg.contains('already_signed')) throw const SignupFailure(SignupFailureKind.alreadySigned);
  if (msg.contains('not_member')) throw const SignupFailure(SignupFailureKind.notMember);
  if (e is PostgrestException || e is TimeoutException) throw const SignupFailure(SignupFailureKind.network);
  throw e;
}

// ---------------- Организации ----------------

class SupabaseOrgRepository implements OrgRepository {
  SupabaseOrgRepository(this._prefs);
  final SharedPreferences _prefs;
  static const _k = 'org.membership';

  Organization _org(Map<String, dynamic> r) => Organization(
        id: r['id'] as String,
        name: r['name'] as String,
        type: _enum(OrgType.values, r['type'], OrgType.ecology),
        cityId: r['city'] as String,
        location: (lat: (r['lat'] as num).toDouble(), lng: (r['lng'] as num).toDouble()),
        members: (r['members'] as num?)?.toInt() ?? 0,
        verified: r['verified'] as bool? ?? false,
      );

  @override
  Future<List<Organization>> list() async => [for (final r in await _db.rpc('org_list') as List) _org(r as Map<String, dynamic>)];

  /// Код проверяет сервер (сам код приложению не виден): заявка подаётся сразу.
  @override
  Future<Organization> findByInviteCode(String code) async {
    try {
      await _db.rpc('request_join', params: {'p_org': null, 'p_code': code.trim().toUpperCase()});
    } on PostgrestException catch (e) {
      throw OrgFailure(e.message.contains('invalid_code') ? 'code_not_found' : 'network');
    }
    final m = await _current();
    return (await list()).firstWhere((o) => o.id == m!.orgId);
  }

  Future<Membership?> _current() async {
    final rows = await _db.rpc('my_membership') as List;
    if (rows.isEmpty) return null;
    final r = rows.first as Map<String, dynamic>;
    return Membership(orgId: r['org_id'] as String, orgName: r['org_name'] as String, status: _enum(MembershipStatus.values, r['status'], MembershipStatus.pending));
  }

  @override
  Future<Membership> requestJoin(Organization org) async {
    await _db.rpc('request_join', params: {'p_org': org.id});
    final m = (await _current())!;
    await save(m);
    return m;
  }

  /// Ответ координатора: опрос раз в 15 с (пока приложение открыто); пуш придёт и в фоне.
  @override
  Future<Membership> awaitDecision(Membership pending) async {
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 15));
      final m = await _current();
      if (m == null || m.orgId != pending.orgId || m.status != MembershipStatus.pending) return m ?? pending;
    }
  }

  @override
  Future<void> cancel(Membership m) async {
    await _db.from('memberships').update({'status': 'left'}).eq('user_id', _me).eq('org_id', m.orgId);
    await save(null);
  }

  @override
  Membership? get saved {
    final raw = _prefs.getString(_k);
    return raw == null ? null : Membership.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  @override
  Future<void> save(Membership? m) async {
    if (m == null) {
      await _prefs.remove(_k);
    } else {
      await _prefs.setString(_k, jsonEncode(m.toJson()));
    }
  }

  /// Подтянуть членство с сервера при запуске.
  Future<Membership?> refresh() async {
    final m = await _current();
    await save(m);
    return m;
  }
}


// ---------------- Квесты и запись ----------------

Quest _quest(Map<String, dynamic> r) => Quest(
      id: r['id'] as String,
      orgId: r['org_id'] as String,
      orgName: r['org_name'] as String,
      title: r['title'] as String,
      description: r['description'] as String? ?? '',
      difficulty: _enum(Difficulty.values, r['difficulty'], Difficulty.easy),
      startsAt: DateTime.parse(r['starts_at'] as String).toLocal(),
      duration: Duration(minutes: (r['duration_min'] as num).toInt()),
      location: (lat: (r['lat'] as num).toDouble(), lng: (r['lng'] as num).toDouble()),
      address: r['address'] as String? ?? '',
      capacity: (r['capacity'] as num).toInt(),
      joined: (r['joined'] as num).toInt(),
      seniorName: r['senior_name'] as String? ?? '',
      checkInAnywhere: r['checkin_anywhere'] as bool? ?? false,
    );

class SupabaseQuestRepository implements QuestRepository {
  @override
  Future<List<Quest>> listForOrg(String orgId) async => [for (final r in await _db.rpc('quest_list', params: {'p_org': orgId}) as List) _quest(r as Map<String, dynamic>)];

  @override
  Future<List<Quest>> listPublic() async => [for (final r in await _db.rpc('quest_list') as List) _quest(r as Map<String, dynamic>)];

  @override
  Future<Quest?> byId(String id) async {
    final all = await listPublic();
    return all.where((q) => q.id == id).firstOrNull;
  }
}

class SupabaseSignupRepository implements SignupRepository {
  @override
  Future<List<Team>> teams(Quest q) async => [
        for (final r in await _db.rpc('team_counts', params: {'p_quest': q.id}) as List)
          Team(
            id: r['team_id'] as String,
            number: (r['number'] as num).toInt(),
            seniorName: r['senior_name'] as String? ?? '',
            capacity: (r['capacity'] as num).toInt(),
            joined: (r['joined'] as num).toInt(),
          ),
      ];

  @override
  Future<Signup> join(Quest q, {Team? team, required List<Signup> mine}) async {
    try {
      final r = await _db.rpc('join_quest', params: {'p_quest': q.id, 'p_team': team?.id}) as Map<String, dynamic>;
      if (r['status'] == 'waitlist') return Signup(quest: q, status: SignupStatus.waitlist, position: (r['waitlist_pos'] as num).toInt());
      final t = (await teams(q)).firstWhere((x) => x.id == r['team_id']);
      return Signup(quest: q, status: SignupStatus.joined, team: t);
    } catch (e) {
      _rethrow(e);
    }
  }

  @override
  Future<void> leave(Signup s) async {
    try {
      await _db.rpc('leave_quest', params: {'p_quest': s.quest.id});
    } catch (e) {
      _rethrow(e);
    }
  }

  /// Мои записи с сервера (при запуске): команда, отметка, итог смены.
  Future<List<Signup>> mine(List<Quest> known) async {
    final rows = await _db.rpc('my_signups') as List;
    final byId = {for (final q in known) q.id: q};
    final missing = rows.map((r) => r['quest_id'] as String).where((id) => !byId.containsKey(id)).toSet();
    if (missing.isNotEmpty) {
      for (final q in await SupabaseQuestRepository().listPublic()) {
        byId[q.id] = q;
      }
    }
    return [
      for (final r in rows.cast<Map<String, dynamic>>())
        if (byId[r['quest_id']] != null)
          Signup(
            quest: byId[r['quest_id']]!,
            status: r['status'] == 'waitlist' ? SignupStatus.waitlist : SignupStatus.joined,
            position: (r['waitlist_pos'] as num?)?.toInt() ?? 0,
            team: r['team_id'] == null
                ? null
                : Team(id: r['team_id'] as String, number: (r['team_number'] as num).toInt(), seniorName: r['senior_name'] as String? ?? '', capacity: (r['team_capacity'] as num).toInt(), joined: (r['team_joined'] as num).toInt()),
            checkedInAt: r['checked_in_at'] == null ? null : DateTime.parse(r['checked_in_at'] as String).toLocal(),
            geoVerified: r['geo_verified'] as bool? ?? false,
            shift: switch (r['report_status']) {
              'approved' => (r['present'] as bool? ?? false) ? ShiftState.approved : ShiftState.missed,
              'sent' => (r['present'] as bool? ?? false) ? ShiftState.reported : ShiftState.missed,
              _ => ShiftState.open,
            },
            hours: (r['hours'] as num?)?.toDouble() ?? 0,
          ),
    ];
  }
}

// ---------------- Смена ----------------

class SupabaseShiftRepository implements ShiftRepository {
  @override
  Future<void> checkIn(Quest q, {LatLng? at, required DateTime time}) =>
      _db.rpc('check_in', params: {'p_quest': q.id, 'p_lat': at?.lat, 'p_lng': at?.lng, 'p_at': time.toUtc().toIso8601String()});

  @override
  Future<void> markPresent(Quest q, String userId, bool present) =>
      _db.rpc('mark_present', params: {'p_quest': q.id, 'p_user': userId, 'p_present': present});

  @override
  Future<List<RosterMember>> roster(Quest q, Team team, {required String myName, Signup? mine}) async {
    final h = q.duration.inMinutes / 60;
    return [
      for (final r in (await _db.rpc('team_roster', params: {'p_quest': q.id}) as List).cast<Map<String, dynamic>>())
        RosterMember(
          id: r['user_id'] as String,
          name: r['name'] as String,
          isMe: r['is_me'] as bool,
          minor: r['minor'] as bool,
          // Ручная отметка старшего хранится как отметка без геометки с marked_by.
          checkedInAt: r['checked_in_at'] == null || (r['marked_by_senior'] as bool) ? null : DateTime.parse(r['checked_in_at'] as String).toLocal(),
          markedBySenior: r['marked_by_senior'] as bool,
          geoVerified: r['geo_verified'] as bool,
          hours: h,
        ),
    ];
  }

  /// Ручные отметки уходят на сервер, затем отчёт с часами (сервер сам ограничит часы).
  @override
  Future<void> submit(ShiftReport report) async {
    for (final m in report.members.where((m) => m.markedBySenior && m.checkedInAt == null)) {
      await _db.rpc('mark_present', params: {'p_quest': report.questId, 'p_user': m.id, 'p_present': true});
    }
    await _db.rpc('close_shift', params: {
      'p_quest': report.questId,
      'p_hours': {for (final m in report.members.where((m) => m.present)) m.id: m.hours},
    });
  }

  /// Решение координатора: опрос раз в 30 с, пока экран открыт (пуш придёт и в фоне).
  @override
  Future<ReportStatus> awaitApproval(ShiftReport report) async {
    while (true) {
      await Future<void>.delayed(const Duration(seconds: 30));
      final r = await _db.from('shift_reports').select('status').eq('team_id', report.teamId).maybeSingle();
      if (r?['status'] == 'approved') return ReportStatus.approved;
      if (r?['status'] == 'rejected') throw StateError('rejected');
    }
  }
}

// ---------------- Люди и друзья ----------------

class SupabasePeopleRepository implements PeopleRepository {
  final _cache = <String, Person>{};

  Person _put(Person p) => _cache[p.id] = p;

  @override
  Person? cached(String id) => _cache[id];

  @override
  Future<List<Person>> search(String query) async {
    if (query.trim().length < 2) return const [];
    final rows = (await _db.rpc('search_people', params: {'p_query': query.trim()}) as List).cast<Map<String, dynamic>>();
    return [
      for (final r in rows)
        _put(Person(
          id: r['id'] as String,
          name: r['name'] as String,
          orgName: r['org_name'] as String? ?? '',
          city: 'astana',
          hours: (r['hours'] as num?)?.toDouble() ?? 0,
          monthHours: 0,
          shifts: 0,
          // Сервер уже применил видимость: нет часов — значит скрыты.
          visibility: r['hours'] == null ? HoursVisibility.onlyMe : HoursVisibility.everyone,
        )),
    ];
  }

  @override
  Future<Person?> byId(String id) async {
    final rows = (await _db.rpc('person_card', params: {'p_user': id}) as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return _put(Person(
      id: id,
      name: r['name'] as String,
      orgName: r['org_name'] as String? ?? '',
      city: 'astana',
      hours: (r['hours'] as num?)?.toDouble() ?? 0,
      monthHours: 0,
      shifts: (r['shifts'] as num?)?.toInt() ?? 0,
      minor: r['minor'] as bool,
      visibility: r['hours'] == null ? HoursVisibility.onlyMe : HoursVisibility.everyone,
    ));
  }

  /// Для рейтинга: участники месяца (сервер уже отфильтровал скрытых).
  @override
  Future<List<Person>> all() async {
    final rows = (await _db.rpc('month_rating') as List).cast<Map<String, dynamic>>();
    return [
      for (final r in rows.where((r) => !(r['is_me'] as bool)))
        _put(Person(id: r['user_id'] as String, name: r['name'] as String, orgName: '', city: 'astana', hours: 0, monthHours: (r['hours'] as num).toDouble(), shifts: 0)),
    ];
  }

  @override
  Future<void> sendRequest(String id) => _db.rpc('send_friend_request', params: {'p_user': id});

  /// Ответ человека: опрос раз в 10 с до 2 минут; дальше заявка остаётся «отправлена».
  @override
  Future<bool> awaitAnswer(String id) async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(seconds: 10));
      final s = await loadFriends();
      if (s!.friends.contains(id)) return true;
      if (!s.outgoing.contains(id)) return false;
    }
    return false;
  }

  @override
  Future<({Set<String> friends, Set<String> outgoing, Set<String> incoming})?> loadFriends() async {
    final rows = (await _db.from('friendships').select('user_a, user_b, requested_by, status') as List).cast<Map<String, dynamic>>();
    final f = <String>{}, o = <String>{}, i = <String>{};
    for (final r in rows) {
      final other = r['user_a'] == _me ? r['user_b'] as String : r['user_a'] as String;
      if (r['status'] == 'accepted') {
        f.add(other);
      } else if (r['requested_by'] == _me) {
        o.add(other);
      } else {
        i.add(other);
      }
      if (!_cache.containsKey(other)) await byId(other); // имя для списков
    }
    return (friends: f, outgoing: o, incoming: i);
  }

  @override
  Future<void> respond(String id, {required bool accept}) => _db.rpc('respond_friend_request', params: {'p_user': id, 'p_accept': accept});

  @override
  Future<void> remove(String id) async {
    final a = _me.compareTo(id) < 0 ? _me : id, b = a == _me ? id : _me;
    await _db.from('friendships').delete().eq('user_a', a).eq('user_b', b);
  }
}

// ---------------- Чаты ----------------

/// Логические адреса приложения (team-…, org-…, dm-…) → id чата на сервере.
class SupabaseChatRepository implements ChatRepository {
  final _ids = <String, String>{};

  Future<String> _resolve(Chat chat) async => _ids[chat.id] ??= await _db.rpc('chat_id_for', params: {'p_key': chat.id}) as String;

  Message _msg(Chat chat, Map<String, dynamic> r, Map<String, String> names) => Message(
        id: r['client_id'] as String? ?? r['id'] as String,
        chatId: chat.id,
        authorId: r['author_id'] == _me ? kMeId : (r['author_id'] as String? ?? ''),
        authorName: names[r['author_id']] ?? '',
        text: r['body'] as String,
        sentAt: DateTime.parse(r['created_at'] as String).toLocal(),
      );

  @override
  Future<List<Message>> history(Chat chat) async {
    final id = await _resolve(chat);
    final rows = (await _db.from('messages').select('id, client_id, author_id, body, created_at').eq('chat_id', id).order('created_at').limit(200) as List).cast<Map<String, dynamic>>();
    final names = await _names(rows.map((r) => r['author_id'] as String?).whereType<String>().toSet());
    return [for (final r in rows) _msg(chat, r, names)];
  }

  // Имена авторов: участники видят друг друга через person_card.
  final _nameCache = <String, String>{};
  Future<Map<String, String>> _names(Set<String> ids) async {
    for (final id in ids.where((x) => x != _me && !_nameCache.containsKey(x))) {
      final rows = await _db.rpc('person_card', params: {'p_user': id}) as List;
      _nameCache[id] = rows.isEmpty ? '' : rows.first['name'] as String;
    }
    return _nameCache;
  }

  @override
  Future<Message> send(Message draft) async {
    final id = await _resolve(Chat(id: draft.chatId, kind: ChatKind.team, title: ''));
    // client_id: повтор из офлайн-очереди не создаст дубль (уникальный ключ на сервере).
    await _db.from('messages').upsert({'chat_id': id, 'author_id': _me, 'body': draft.text, 'client_id': draft.id}, onConflict: 'author_id,client_id', ignoreDuplicates: true);
    return draft.withStatus(MessageStatus.sent);
  }

  @override
  Stream<Message> incoming(Chat chat, Message sent) => const Stream.empty(); // ответы приходят через watch

  @override
  Stream<Message> watch(Chat chat) {
    final ctrl = StreamController<Message>();
    RealtimeChannel? ch;
    ctrl.onListen = () async {
      final id = await _resolve(chat);
      ch = _db
          .channel('chat:$id')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'messages',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'chat_id', value: id),
            callback: (p) async {
              final r = p.newRecord;
              if (r['author_id'] == _me) return; // свои уже на экране
              final names = await _names({if (r['author_id'] != null) r['author_id'] as String});
              ctrl.add(_msg(chat, r, names));
            },
          )
          .subscribe();
    };
    ctrl.onCancel = () => ch?.unsubscribe();
    return ctrl.stream;
  }

  @override
  Future<void> report({required String chatId, String? messageId, String? userId, required ReportReason reason}) async {
    String? serverChat;
    try {
      serverChat = _ids[chatId] ?? await _db.rpc('chat_id_for', params: {'p_key': chatId}) as String;
    } catch (_) {}
    await _db.from('abuse_reports').insert({'reporter': _me, 'chat_id': serverChat, 'target_user': userId, 'reason': reason.name});
  }

  @override
  Future<void> block(String userId, {required bool blocked}) async {
    if (blocked) {
      await _db.from('blocks').upsert({'blocker': _me, 'blocked': userId});
    } else {
      await _db.from('blocks').delete().eq('blocker', _me).eq('blocked', userId);
    }
  }
}

/// Номер портфолио с сервера (случайный, можно перевыпустить).
Future<String> serverPortfolioCode({bool reissue = false}) async => await _db.rpc('my_portfolio_code', params: {'p_reissue': reissue}) as String;
