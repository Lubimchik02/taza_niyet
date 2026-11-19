-- Taza Niyet — выборки для приложения одним вызовом (этап 12b).

-- Организации с числом волонтёров (без кода приглашения).
create function org_list() returns table (id uuid, name text, type text, city text, lat double precision, lng double precision, verified boolean, members bigint)
language sql stable security definer set search_path = public as $$
  select o.id, o.name, o.type, o.city, o.lat, o.lng, o.verified,
         (select count(*) from memberships m where m.org_id = o.id and m.status = 'active')
  from organizations o where o.accepts_new order by o.name
$$;

create function my_membership() returns table (org_id uuid, org_name text, status membership_status, role org_role)
language sql stable security definer set search_path = public as $$
  select m.org_id, o.name, m.status, m.role from memberships m join organizations o on o.id = m.org_id
  where m.user_id = auth.uid() and m.status in ('pending', 'active', 'rejected')
  order by (m.status = 'rejected'), m.created_at desc limit 1
$$;

-- Квесты: своей организации (p_org) или все опубликованные города; с занятостью и старшим первой команды.
create function quest_list(p_org uuid default null, p_city text default 'astana')
returns table (id uuid, org_id uuid, org_name text, title text, description text, difficulty difficulty, starts_at timestamptz,
               duration_min int, lat double precision, lng double precision, address text, capacity int, joined bigint, senior_name text)
language sql stable security definer set search_path = public as $$
  select q.id, q.org_id, o.name, q.title, q.description, q.difficulty, q.starts_at, q.duration_min, q.lat, q.lng, q.address, q.capacity,
         (select count(*) from signups s where s.quest_id = q.id and s.status = 'joined'),
         (select p.name from teams t join profiles p on p.id = t.senior_id where t.quest_id = q.id order by t.number limit 1)
  from quests q join organizations o on o.id = q.org_id
  where q.status = 'published' and shift_end(q) > now()
    and (p_org is null and o.city = p_city or q.org_id = p_org)
  order by q.starts_at
$$;

-- Мои записи с командой, отметкой и итогами смены.
create function my_signups()
returns table (quest_id uuid, status signup_status, waitlist_pos int, team_id uuid, team_number int, team_capacity int, team_joined bigint,
               senior_name text, i_am_senior boolean, checked_in_at timestamptz, geo_verified boolean, report_status report_status, hours numeric, present boolean)
language sql stable security definer set search_path = public as $$
  select s.quest_id, s.status, s.waitlist_pos, t.id, t.number, t.capacity,
         (select count(*) from signups x where x.team_id = t.id and x.status = 'joined'),
         p.name, t.senior_id = auth.uid(), c.at, c.geo_verified, r.status, i.hours, i.present
  from signups s
  left join teams t on t.id = s.team_id
  left join profiles p on p.id = t.senior_id
  left join check_ins c on c.signup_id = s.id
  left join shift_reports r on r.team_id = t.id
  left join shift_report_items i on i.report_id = r.id and i.user_id = s.user_id
  where s.user_id = auth.uid() and s.status <> 'cancelled'
$$;

-- Список команды для старшего.
create function team_roster(p_quest uuid)
returns table (user_id uuid, name text, minor boolean, checked_in_at timestamptz, geo_verified boolean, marked_by_senior boolean, is_me boolean)
language sql stable security definer set search_path = public as $$
  select pr.id, pr.name, is_minor(pr.birth_year), c.at, coalesce(c.geo_verified, false), c.marked_by is not null, pr.id = auth.uid()
  from teams t join signups s on s.team_id = t.id and s.status = 'joined'
  join profiles pr on pr.id = s.user_id left join check_ins c on c.signup_id = s.id
  where t.quest_id = p_quest and t.senior_id = auth.uid()
  order by pr.id = auth.uid() desc, pr.name
$$;

-- Чат по «логическому» адресу приложения: team-<team_id> | org-<org_id> | dm-<user_id>.
create function chat_id_for(p_key text) returns uuid language plpgsql security definer set search_path = public as $$
declare k text := split_part(p_key, '-', 1); v uuid := substr(p_key, length(k) + 2)::uuid; cid uuid;
begin
  if k = 'team' then select id into cid from chats where team_id = v;
  elsif k = 'org' then select id into cid from chats where kind = 'channel' and org_id = v;
  elsif k = 'dm' then return open_direct_chat(v);
  end if;
  if cid is null or not is_member(cid) then raise exception 'not_member'; end if;
  return cid;
end $$;

-- Устройство для пушей.
create function register_push_token(p_token text, p_platform text) returns void
language sql security definer set search_path = public as $$
  insert into push_tokens (token, user_id, platform) values (p_token, auth.uid(), p_platform)
  on conflict (token) do update set user_id = excluded.user_id, platform = excluded.platform, updated_at = now()
$$;

-- Входящие сообщения → уведомления участникам (кроме автора, «без звука» и заблокировавших автора).
create function messages_notify() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into notifications (user_id, kind, args, route)
  select cm.user_id, 'chat', jsonb_build_object('name', (select name from profiles where id = new.author_id), 'text', left(new.body, 120)),
         '/chat/' || case c.kind when 'team' then 'team-' || c.team_id when 'channel' then 'org-' || c.org_id
                                 else 'dm-' || new.author_id end
  from chat_members cm join chats c on c.id = cm.chat_id
  where cm.chat_id = new.chat_id and cm.user_id <> new.author_id and not cm.muted
    and not exists (select 1 from blocks b where b.blocker = cm.user_id and b.blocked = new.author_id);
  return new;
end $$;
create trigger messages_notify after insert on messages for each row execute function messages_notify();

-- Realtime: приложение подписывается на новые сообщения своих чатов и на свои уведомления.
do $$ begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table messages, notifications;
  end if;
end $$;
