-- Taza Niyet — серверная логика (этап 12).
-- Всё, что влияет на часы, места и доступ, проверяется здесь, а не в приложении:
-- телефон можно подделать, базу — нет.

-- ---------- Вспомогательное ----------
create function is_minor(p_birth_year int) returns boolean language sql stable as $$
  select extract(year from now())::int - p_birth_year - 1 < 18
$$;

create function haversine_m(lat1 double precision, lng1 double precision, lat2 double precision, lng2 double precision)
returns int language sql immutable as $$
  select round(2 * 6371000 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2))))::int
$$;

create function my_role(p_org uuid) returns org_role language sql stable security definer set search_path = public as $$
  select role from memberships where user_id = auth.uid() and org_id = p_org and status = 'active'
$$;

create function is_coordinator(p_org uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(my_role(p_org) = 'coordinator', false)
$$;

create function are_friends(a uuid, b uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from friendships where user_a = least(a, b) and user_b = greatest(a, b) and status = 'accepted')
$$;

create function is_blocked(a uuid, b uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from blocks where (blocker = a and blocked = b) or (blocker = b and blocked = a))
$$;

-- Видны ли мне часы человека: «все» / «друзья» / «только я»; до 18 лет — максимум друзья.
create function can_see_hours(p_user uuid) returns boolean language sql stable security definer set search_path = public as $$
  select p.id = auth.uid() or case
    when p.visibility = 'only_me' then false
    when p.visibility = 'friends' or is_minor(p.birth_year) then are_friends(p.id, auth.uid())
    else true end
  from profiles p where p.id = p_user
$$;

create function notify(p_user uuid, p_kind text, p_args jsonb, p_route text) returns void
language sql security definer set search_path = public as $$
  insert into notifications (user_id, kind, args, route) values (p_user, p_kind, p_args, p_route)
$$;

create function shift_end(q quests) returns timestamptz language sql immutable as $$
  select q.starts_at + make_interval(mins => q.duration_min)
$$;

-- ---------- Организация ----------
create function request_join(p_org uuid, p_code text default null) returns membership_status
language plpgsql security definer set search_path = public as $$
declare o organizations;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  if p_code is not null then
    select * into o from organizations where invite_code = upper(p_code);
    if not found then raise exception 'invalid_code'; end if;
  else
    select * into o from organizations where id = p_org;
    if not found then raise exception 'not_found'; end if;
  end if;
  if not o.accepts_new then raise exception 'org_closed'; end if;
  -- Новая заявка заменяет прежнюю (одна организация одновременно).
  update memberships set status = 'left' where user_id = auth.uid() and status in ('pending', 'active') and org_id <> o.id;
  insert into memberships (user_id, org_id, status) values (auth.uid(), o.id, 'pending')
    on conflict (user_id, org_id) do update set status = 'pending', created_at = now(), decided_at = null
    where memberships.status in ('rejected', 'left');
  return (select status from memberships where user_id = auth.uid() and org_id = o.id);
end $$;

create function decide_membership(p_user uuid, p_org uuid, p_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_coordinator(p_org) then raise exception 'forbidden'; end if;
  update memberships set status = case when p_approve then 'active'::membership_status else 'rejected' end, decided_at = now()
    where user_id = p_user and org_id = p_org and status = 'pending';
  if not found then raise exception 'not_pending'; end if;
  perform notify(p_user, case when p_approve then 'org_approved' else 'org_rejected' end,
    jsonb_build_object('org', (select name from organizations where id = p_org)), case when p_approve then '/map' else '/org' end);
  if p_approve then
    insert into chat_members (chat_id, user_id) select id, p_user from chats where kind = 'channel' and org_id = p_org on conflict do nothing;
  end if;
end $$;

-- ---------- Квесты: команды создаются автоматически по 10 мест, канал организации — при её создании ----------
create function make_teams() returns trigger language plpgsql security definer set search_path = public as $$
declare n int := least(5, greatest(1, ceil(new.capacity / 10.0)::int)); i int;
begin
  for i in 1..n loop
    insert into teams (quest_id, number, capacity) values (new.id, i, new.capacity / n + case when i <= new.capacity % n then 1 else 0 end);
  end loop;
  return new;
end $$;
create trigger quests_make_teams after insert on quests for each row execute function make_teams();

create function make_team_chat() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into chats (kind, team_id, org_id) select 'team', new.id, q.org_id from quests q where q.id = new.quest_id;
  return new;
end $$;
create trigger teams_make_chat after insert on teams for each row execute function make_team_chat();

create function make_org_channel() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into chats (kind, org_id) values ('channel', new.id);
  return new;
end $$;
create trigger organizations_make_channel after insert on organizations for each row execute function make_org_channel();

-- ---------- Запись на квест ----------
create function join_quest(p_quest uuid, p_team uuid default null) returns signups
language plpgsql security definer set search_path = public as $$
declare q quests; t teams; s signups; me uuid := auth.uid(); pos int;
begin
  if me is null then raise exception 'not_authenticated'; end if;
  select * into q from quests where id = p_quest and status = 'published' for update;  -- блокировка: двое не займут одно место
  if not found then raise exception 'not_found'; end if;
  if shift_end(q) < now() then raise exception 'quest_over'; end if;
  if coalesce(my_role(q.org_id)::text, '') = '' then raise exception 'not_member'; end if;
  if exists (select 1 from signups where quest_id = q.id and user_id = me and status <> 'cancelled') then raise exception 'already_signed'; end if;
  if exists (select 1 from signups s2 join quests q2 on q2.id = s2.quest_id
             where s2.user_id = me and s2.status = 'joined' and q2.starts_at < shift_end(q) and q.starts_at < shift_end(q2)) then
    raise exception 'time_conflict';
  end if;
  select tm.* into t from teams tm
    where tm.quest_id = q.id and (p_team is null or tm.id = p_team)
      and (select count(*) from signups where team_id = tm.id and status = 'joined') < tm.capacity
    order by tm.number limit 1;
  if found then
    insert into signups (quest_id, team_id, user_id, status) values (q.id, t.id, me, 'joined') returning * into s;
    insert into chat_members (chat_id, user_id) select id, me from chats where team_id = t.id on conflict do nothing;
  else
    select coalesce(max(waitlist_pos), 0) + 1 into pos from signups where quest_id = q.id and status = 'waitlist';
    insert into signups (quest_id, user_id, status, waitlist_pos) values (q.id, me, 'waitlist', pos) returning * into s;
  end if;
  return s;
end $$;

-- Отмена: место переходит первому из листа ожидания (без пересечений по времени).
create function leave_quest(p_quest uuid) returns void
language plpgsql security definer set search_path = public as $$
declare s signups; nxt signups; q quests;
begin
  select * into q from quests where id = p_quest for update;
  select * into s from signups where quest_id = p_quest and user_id = auth.uid() and status <> 'cancelled';
  if not found then raise exception 'not_signed'; end if;
  if exists (select 1 from check_ins where signup_id = s.id) then raise exception 'already_checked_in'; end if;
  update signups set status = 'cancelled', cancelled_at = now(), waitlist_pos = null where id = s.id;
  delete from chat_members where user_id = auth.uid() and chat_id in (select id from chats where team_id = s.team_id);
  if s.status = 'joined' then
    select * into nxt from signups w where w.quest_id = p_quest and w.status = 'waitlist'
      and not exists (select 1 from signups s2 join quests q2 on q2.id = s2.quest_id
                      where s2.user_id = w.user_id and s2.status = 'joined' and q2.starts_at < shift_end(q) and q.starts_at < shift_end(q2))
      order by w.waitlist_pos limit 1;
    if found then
      update signups set status = 'joined', team_id = s.team_id, waitlist_pos = null where id = nxt.id;
      insert into chat_members (chat_id, user_id) select id, nxt.user_id from chats where team_id = s.team_id on conflict do nothing;
      perform notify(nxt.user_id, 'waitlist_promoted', jsonb_build_object('quest', q.title), '/quest/' || q.id);
    end if;
  end if;
end $$;

-- ---------- Смена ----------
-- «Я на месте». p_at — время на телефоне: отметка из офлайн-очереди может прийти позже,
-- но не раньше, чем за 30 минут до начала, не позже конца смены и не «из будущего».
create function check_in(p_quest uuid, p_lat double precision, p_lng double precision, p_at timestamptz default now())
returns check_ins language plpgsql security definer set search_path = public as $$
declare q quests; s signups; d int; c check_ins;
begin
  select * into q from quests where id = p_quest;
  select * into s from signups where quest_id = p_quest and user_id = auth.uid() and status = 'joined';
  if not found then raise exception 'not_signed'; end if;
  if p_at > now() + interval '5 minutes' then raise exception 'bad_time'; end if;
  if p_at < q.starts_at - interval '30 minutes' or p_at > shift_end(q) then raise exception 'outside_window'; end if;
  d := case when p_lat is null then null else haversine_m(p_lat, p_lng, q.lat, q.lng) end;
  insert into check_ins (signup_id, at, lat, lng, distance_m, geo_verified)
    values (s.id, p_at, p_lat, p_lng, d, coalesce(d <= 300, false))
    on conflict (signup_id) do nothing returning * into c;
  if c is null then select * into c from check_ins where signup_id = s.id; end if;  -- повтор из очереди — без ошибки
  return c;
end $$;

create function senior_team(p_quest uuid) returns teams language sql stable security definer set search_path = public as $$
  select * from teams where quest_id = p_quest and senior_id = auth.uid()
$$;

-- Старший отмечает пришедшего без геометки (или снимает свою ручную отметку).
create function mark_present(p_quest uuid, p_user uuid, p_present boolean) returns void
language plpgsql security definer set search_path = public as $$
declare t teams := senior_team(p_quest); s signups;
begin
  if t.id is null then raise exception 'not_senior'; end if;
  if exists (select 1 from shift_reports where team_id = t.id) then raise exception 'already_closed'; end if;
  select * into s from signups where team_id = t.id and user_id = p_user and status = 'joined';
  if not found then raise exception 'not_in_team'; end if;
  if p_present then
    insert into check_ins (signup_id, at, marked_by) values (s.id, now(), auth.uid()) on conflict (signup_id) do nothing;
  else
    delete from check_ins where signup_id = s.id and marked_by = auth.uid();  -- геометку самого волонтёра снять нельзя
  end if;
end $$;

-- Закрыть смену. p_hours: {"<user_id>": 2.5, ...}; не указан — длительность квеста.
-- Часы: 0..длительность, шаг 0,5. Отсутствующие получают 0.
create function close_shift(p_quest uuid, p_hours jsonb default '{}') returns shift_reports
language plpgsql security definer set search_path = public as $$
declare t teams := senior_team(p_quest); q quests; r shift_reports; max_h numeric;
begin
  if t.id is null then raise exception 'not_senior'; end if;
  select * into q from quests where id = p_quest;
  if now() < q.starts_at then raise exception 'not_started'; end if;
  max_h := q.duration_min / 60.0;
  insert into shift_reports (quest_id, team_id, senior_id) values (p_quest, t.id, auth.uid()) returning * into r;
  insert into shift_report_items (report_id, user_id, present, hours, manual)
  select r.id, s.user_id, c.signup_id is not null,
         case when c.signup_id is null then 0
              else least(max_h, greatest(0, round(coalesce((p_hours ->> s.user_id::text)::numeric, max_h) * 2) / 2)) end,
         c.marked_by is not null
  from signups s left join check_ins c on c.signup_id = s.id
  where s.team_id = t.id and s.status = 'joined';
  perform notify(m.user_id, 'shift_report', jsonb_build_object('quest', q.title, 'manual', (select count(*) from shift_report_items where report_id = r.id and manual)), '/coordinator/reports/' || r.id)
    from memberships m where m.org_id = q.org_id and m.role = 'coordinator' and m.status = 'active';
  return r;
end $$;

-- Координатор подтверждает: начисления (1 ч = 5 Tz) и бонус старшему +10 Tz.
create function approve_shift(p_report uuid, p_approve boolean, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare r shift_reports; q quests; o organizations; it record;
begin
  select * into r from shift_reports where id = p_report for update;
  if not found or r.status <> 'sent' then raise exception 'not_pending'; end if;
  select * into q from quests where id = r.quest_id;
  select * into o from organizations where id = q.org_id;
  if not is_coordinator(q.org_id) then raise exception 'forbidden'; end if;
  update shift_reports set status = case when p_approve then 'approved'::report_status else 'rejected' end,
    decided_by = auth.uid(), decided_at = now(), note = p_note where id = r.id;
  if not p_approve then
    perform notify(r.senior_id, 'shift_rejected', jsonb_build_object('quest', q.title, 'note', p_note), '/quest/' || q.id);
    return;
  end if;
  for it in select * from shift_report_items where report_id = r.id and present and hours > 0 loop
    insert into credits (user_id, org_id, quest_id, report_id, kind, hours, tz, quest_title, org_name, shift_date)
      values (it.user_id, o.id, q.id, r.id, 'shift', it.hours, round(it.hours * 5), q.title, o.name, q.starts_at::date);
    perform notify(it.user_id, 'hours_approved', jsonb_build_object('tz', round(it.hours * 5), 'quest', q.title), '/profile/portfolio');
  end loop;
  insert into credits (user_id, org_id, quest_id, report_id, kind, tz, quest_title, org_name, shift_date)
    values (r.senior_id, o.id, q.id, r.id, 'senior_bonus', 10, q.title, o.name, q.starts_at::date);
end $$;

-- Штраф старшему за ошибки в учёте (после проверки координатором). Только минус баллы, часы не трогаем.
create function penalize(p_report uuid, p_tz int, p_note text) returns void
language plpgsql security definer set search_path = public as $$
declare r shift_reports; q quests; o organizations;
begin
  select * into r from shift_reports where id = p_report;
  select * into q from quests where id = r.quest_id;
  select * into o from organizations where id = q.org_id;
  if not is_coordinator(q.org_id) then raise exception 'forbidden'; end if;
  if p_tz not between 1 and 50 then raise exception 'bad_amount'; end if;
  insert into credits (user_id, org_id, quest_id, report_id, kind, tz, quest_title, org_name, shift_date)
    values (r.senior_id, o.id, q.id, r.id, 'penalty', -p_tz, q.title, o.name, q.starts_at::date);
  perform notify(r.senior_id, 'penalty', jsonb_build_object('tz', p_tz, 'note', p_note, 'quest', q.title), '/profile');
end $$;

-- ---------- Люди, друзья, рейтинг ----------
create view my_totals with (security_invoker = true) as
  select coalesce(sum(hours), 0) as hours, coalesce(sum(tz), 0) as tz, count(*) filter (where kind = 'shift') as shifts
  from credits where user_id = auth.uid();

-- Поиск: только те, кто разрешил; часы — только если видны мне.
create function search_people(p_query text)
returns table (id uuid, name text, org_name text, hours numeric, is_friend boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, o.name,
         case when can_see_hours(p.id) then (select coalesce(sum(c.hours), 0) from credits c where c.user_id = p.id) end,
         are_friends(p.id, auth.uid())
  from profiles p
  left join memberships m on m.user_id = p.id and m.status = 'active'
  left join organizations o on o.id = m.org_id
  where char_length(trim(p_query)) >= 2 and p.id <> auth.uid() and p.deletion_requested_at is null
    and (p.show_in_search or are_friends(p.id, auth.uid())) and not is_blocked(p.id, auth.uid())
    and (lower(p.name) like lower(trim(p_query)) || '%'                 -- начало имени
         or lower(p.name) like '% ' || lower(trim(p_query)) || '%'      -- начало фамилии
         or similarity(lower(p.name), lower(trim(p_query))) > 0.35)    -- опечатка
  order by similarity(lower(p.name), lower(trim(p_query))) desc
  limit 30
$$;

-- Рейтинг месяца: подтверждённые часы, только кто участвует и чьи часы мне видны; я — всегда.
create function month_rating(p_org uuid default null, p_city text default null)
returns table (place int, user_id uuid, name text, hours numeric, is_me boolean)
language sql stable security definer set search_path = public as $$
  with h as (
    select c.user_id, sum(c.hours) as hours from credits c
    where c.kind = 'shift' and c.shift_date >= date_trunc('month', now())::date
      and (p_org is null or c.org_id = p_org)
    group by c.user_id
  ), visible as (
    select p.id, p.name, coalesce(h.hours, 0) as hours, p.id = auth.uid() as is_me
    from profiles p left join h on h.user_id = p.id
    where (p.id = auth.uid() or (h.hours > 0 and p.show_in_rating and can_see_hours(p.id)))
      and (p_city is null or p.city = p_city)
      and (p_org is null or p.id = auth.uid() or exists (select 1 from memberships m where m.user_id = p.id and m.org_id = p_org and m.status = 'active'))
  )
  select rank() over (order by hours desc)::int, id, name, hours, is_me from visible order by hours desc, name limit 100
$$;

create function send_friend_request(p_user uuid) returns friend_status
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); target profiles; st friend_status;
begin
  select * into target from profiles where id = p_user;
  if not found or p_user = me then raise exception 'not_found'; end if;
  if is_blocked(me, p_user) then raise exception 'blocked'; end if;
  if target.who_can_add = 'nobody' then raise exception 'not_allowed'; end if;
  if target.who_can_add = 'my_org' and not exists (
      select 1 from memberships a join memberships b on a.org_id = b.org_id
      where a.user_id = me and b.user_id = p_user and a.status = 'active' and b.status = 'active') then
    raise exception 'not_allowed';
  end if;
  insert into friendships (user_a, user_b, requested_by) values (least(me, p_user), greatest(me, p_user), me)
    on conflict (user_a, user_b) do update set status = case
      when friendships.requested_by <> me then 'accepted'::friend_status else friendships.status end  -- встречная заявка = согласие
    returning status into st;
  perform notify(p_user, case when st = 'accepted' then 'friend_accepted' else 'friend_request' end,
    jsonb_build_object('name', (select name from profiles where id = me)), '/people/' || me);
  return st;
end $$;

create function respond_friend_request(p_user uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid();
begin
  if p_accept then
    update friendships set status = 'accepted' where user_a = least(me, p_user) and user_b = greatest(me, p_user) and requested_by = p_user and status = 'pending';
    if found then perform notify(p_user, 'friend_accepted', jsonb_build_object('name', (select name from profiles where id = me)), '/people/' || me); end if;
  else
    delete from friendships where user_a = least(me, p_user) and user_b = greatest(me, p_user) and requested_by = p_user and status = 'pending';
  end if;
end $$;

-- Личный чат — только между друзьями.
create function open_direct_chat(p_user uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := auth.uid(); k text := least(me, p_user)::text || ':' || greatest(me, p_user)::text; cid uuid;
begin
  if not are_friends(me, p_user) then raise exception 'not_friends'; end if;
  if is_blocked(me, p_user) then raise exception 'blocked'; end if;
  insert into chats (kind, direct_key) values ('direct', k) on conflict (direct_key) do nothing returning id into cid;
  if cid is null then select id into cid from chats where direct_key = k; end if;
  insert into chat_members (chat_id, user_id) values (cid, me), (cid, p_user) on conflict do nothing;
  return cid;
end $$;

-- ---------- Портфолио: публичная проверка (без входа) ----------
create function verify_portfolio(p_code text)
returns table (name text, hours numeric, tz bigint, shifts bigint, items jsonb)
language sql stable security definer set search_path = public as $$
  select p.name, coalesce(sum(c.hours), 0), coalesce(sum(c.tz), 0), count(c.*) filter (where c.kind = 'shift'),
         coalesce(jsonb_agg(jsonb_build_object('quest', c.quest_title, 'org', c.org_name, 'date', c.shift_date, 'hours', c.hours) order by c.shift_date desc)
                  filter (where c.kind = 'shift'), '[]')
  from portfolio_tokens t join profiles p on p.id = t.user_id left join credits c on c.user_id = p.id
  where t.code = upper(p_code) and t.revoked_at is null and p.deletion_requested_at is null
  group by p.name
$$;

create function my_portfolio_code(p_reissue boolean default false) returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if p_reissue then delete from portfolio_tokens where user_id = auth.uid(); end if;
  insert into portfolio_tokens (user_id) values (auth.uid()) on conflict (user_id) do nothing;
  select code into c from portfolio_tokens where user_id = auth.uid();
  return c;
end $$;

-- ---------- Удаление аккаунта ----------
create function request_account_deletion() returns void language sql security definer set search_path = public as $$
  update profiles set deletion_requested_at = now() where id = auth.uid()
$$;

create function cancel_account_deletion() returns void language sql security definer set search_path = public as $$
  update profiles set deletion_requested_at = null where id = auth.uid()
$$;

-- Ежедневно (pg_cron): удалить тех, кто не передумал за 30 дней. Часы в credits остаются без имени (user_id → null).
create function purge_deleted_accounts() returns int language plpgsql security definer set search_path = public, auth as $$
declare n int;
begin
  with gone as (delete from auth.users where id in (select id from profiles where deletion_requested_at < now() - interval '30 days') returning 1)
  select count(*) into n from gone;
  return n;
end $$;
