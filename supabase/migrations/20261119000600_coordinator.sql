-- Taza Niyet — веб-кабинет координатора (этап 12c). Всё — только для координатора своей организации.

create function assert_coordinator(p_org uuid) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if not is_coordinator(p_org) then raise exception 'forbidden'; end if;
end $$;

-- Обзор: что ждёт решения.
create function coord_overview(p_org uuid)
returns table (pending_members bigint, pending_reports bigint, open_abuse bigint, quests_week bigint, members bigint, month_hours numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform assert_coordinator(p_org);
  return query select
    (select count(*) from memberships where org_id = p_org and status = 'pending'),
    (select count(*) from shift_reports r join quests q on q.id = r.quest_id where q.org_id = p_org and r.status = 'sent'),
    (select count(*) from abuse_reports a where a.resolved_at is null and (
        a.chat_id in (select id from chats where org_id = p_org)
        or a.target_user in (select user_id from memberships where org_id = p_org and status = 'active'))),
    (select count(*) from quests where org_id = p_org and status = 'published' and starts_at between now() and now() + interval '7 days'),
    (select count(*) from memberships where org_id = p_org and status = 'active'),
    (select coalesce(sum(hours), 0) from credits where org_id = p_org and kind = 'shift' and shift_date >= date_trunc('month', now())::date);
end $$;

-- Волонтёры и заявки организации.
create function coord_members(p_org uuid)
returns table (user_id uuid, name text, minor boolean, status membership_status, role org_role, joined_at timestamptz, total_hours numeric, month_hours numeric, shifts bigint)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform assert_coordinator(p_org);
  return query
    select m.user_id, p.name, is_minor(p.birth_year), m.status, m.role, m.created_at,
           coalesce((select sum(c.hours) from credits c where c.user_id = m.user_id and c.org_id = p_org), 0),
           coalesce((select sum(c.hours) from credits c where c.user_id = m.user_id and c.org_id = p_org and c.shift_date >= date_trunc('month', now())::date), 0),
           (select count(*) from credits c where c.user_id = m.user_id and c.org_id = p_org and c.kind = 'shift')
    from memberships m join profiles p on p.id = m.user_id
    where m.org_id = p_org and m.status in ('pending', 'active')
    order by m.status = 'active', m.created_at;
end $$;

create function coord_set_role(p_org uuid, p_user uuid, p_role org_role) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_coordinator(p_org);
  if p_user = auth.uid() then raise exception 'self'; end if;
  update memberships set role = p_role where org_id = p_org and user_id = p_user and status = 'active';
  if not found then raise exception 'not_member'; end if;
end $$;

-- Исключить из организации (записи на будущие квесты отменяются).
create function coord_remove_member(p_org uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  perform assert_coordinator(p_org);
  update memberships set status = 'left' where org_id = p_org and user_id = p_user and status = 'active' and role <> 'coordinator';
  update signups s set status = 'cancelled', cancelled_at = now(), waitlist_pos = null
    from quests q where q.id = s.quest_id and q.org_id = p_org and s.user_id = p_user and s.status <> 'cancelled' and q.starts_at > now();
end $$;

create function coord_invite_code(p_org uuid, p_regenerate boolean default false) returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  perform assert_coordinator(p_org);
  if p_regenerate then
    update organizations set invite_code = substr(gen_portfolio_code(), 3) || substr(gen_portfolio_code(), 3, 2) where id = p_org;
  end if;
  select invite_code into c from organizations where id = p_org;
  return c;
end $$;

-- Квесты организации (включая черновики и отменённые) с занятостью.
create function coord_quests(p_org uuid)
returns table (id uuid, title text, starts_at timestamptz, duration_min int, capacity int, joined bigint, waitlist bigint, status quest_status, difficulty difficulty, address text, teams jsonb)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform assert_coordinator(p_org);
  return query
    select q.id, q.title, q.starts_at, q.duration_min, q.capacity,
           (select count(*) from signups s where s.quest_id = q.id and s.status = 'joined'),
           (select count(*) from signups s where s.quest_id = q.id and s.status = 'waitlist'),
           q.status, q.difficulty, q.address,
           (select jsonb_agg(jsonb_build_object('id', t.id, 'number', t.number, 'capacity', t.capacity, 'senior_id', t.senior_id,
                    'senior_name', (select name from profiles where id = t.senior_id),
                    'joined', (select count(*) from signups s where s.team_id = t.id and s.status = 'joined')) order by t.number)
            from teams t where t.quest_id = q.id)
    from quests q where q.org_id = p_org order by q.starts_at desc limit 200;
end $$;

-- Старшим команды может быть только старший или координатор организации; он же добавляется в чат команды.
create function coord_assign_senior(p_team uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare q quests;
begin
  select qq.* into q from quests qq join teams t on t.quest_id = qq.id where t.id = p_team;
  perform assert_coordinator(q.org_id);
  if p_user is not null and not exists (select 1 from memberships where org_id = q.org_id and user_id = p_user and status = 'active' and role in ('senior', 'coordinator')) then
    raise exception 'not_senior';
  end if;
  update teams set senior_id = p_user where id = p_team;
  if p_user is not null then
    insert into chat_members (chat_id, user_id) select id, p_user from chats where team_id = p_team on conflict do nothing;
  end if;
end $$;

-- Отменить квест: всем записанным — уведомление.
create function coord_cancel_quest(p_quest uuid) returns void
language plpgsql security definer set search_path = public as $$
declare q quests;
begin
  select * into q from quests where id = p_quest;
  perform assert_coordinator(q.org_id);
  update quests set status = 'cancelled' where id = p_quest;
  perform notify(s.user_id, 'quest_cancelled', jsonb_build_object('quest', q.title), '/map')
    from signups s where s.quest_id = p_quest and s.status <> 'cancelled';
  update signups set status = 'cancelled', cancelled_at = now(), waitlist_pos = null where quest_id = p_quest and status <> 'cancelled';
end $$;

-- Отчёты смен организации.
create function coord_reports(p_org uuid, p_status report_status default 'sent')
returns table (id uuid, quest_id uuid, quest_title text, starts_at timestamptz, team_number int, senior_name text, submitted_at timestamptz,
               status report_status, present bigint, absent bigint, manual bigint, total_hours numeric)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform assert_coordinator(p_org);
  return query
    select r.id, q.id, q.title, q.starts_at, t.number, p.name, r.submitted_at, r.status,
           (select count(*) from shift_report_items i where i.report_id = r.id and i.present),
           (select count(*) from shift_report_items i where i.report_id = r.id and not i.present),
           (select count(*) from shift_report_items i where i.report_id = r.id and i.manual),
           (select coalesce(sum(i.hours), 0) from shift_report_items i where i.report_id = r.id and i.present)
    from shift_reports r join quests q on q.id = r.quest_id join teams t on t.id = r.team_id left join profiles p on p.id = r.senior_id
    where q.org_id = p_org and r.status = p_status
    order by r.submitted_at desc;
end $$;

-- Подробно: кто, как отметился (геометка/вручную, время, расстояние), сколько часов поставил старший.
create function coord_report_items(p_report uuid)
returns table (user_id uuid, name text, minor boolean, present boolean, hours numeric, manual boolean, checked_in_at timestamptz, distance_m int, geo_verified boolean)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
declare q quests;
begin
  select qq.* into q from quests qq join shift_reports r on r.quest_id = qq.id where r.id = p_report;
  perform assert_coordinator(q.org_id);
  return query
    select i.user_id, p.name, is_minor(p.birth_year), i.present, i.hours, i.manual, c.at, c.distance_m, coalesce(c.geo_verified, false)
    from shift_report_items i join profiles p on p.id = i.user_id
    left join signups s on s.quest_id = q.id and s.user_id = i.user_id and s.status = 'joined'
    left join check_ins c on c.signup_id = s.id
    where i.report_id = p_report
    order by i.manual desc, i.present desc, p.name;
end $$;

-- Пост в канал организации от координатора.
create function coord_post(p_org uuid, p_body text) returns void
language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  perform assert_coordinator(p_org);
  select id into cid from chats where kind = 'channel' and org_id = p_org;
  insert into chat_members (chat_id, user_id) values (cid, auth.uid()) on conflict do nothing;
  insert into messages (chat_id, author_id, body) values (cid, auth.uid(), p_body);
end $$;

-- Жалобы, связанные с организацией (чаты организации или её волонтёры).
create function coord_abuse(p_org uuid)
returns table (id bigint, reason report_reason, created_at timestamptz, reporter_name text, target_id uuid, target_name text, message text, chat_kind chat_kind)
language plpgsql stable security definer set search_path = public as $$
#variable_conflict use_column
begin
  perform assert_coordinator(p_org);
  return query
    select a.id, a.reason, a.created_at, rp.name, a.target_user, tp.name, m.body, c.kind
    from abuse_reports a
    left join profiles rp on rp.id = a.reporter
    left join profiles tp on tp.id = a.target_user
    left join messages m on m.id = a.message_id
    left join chats c on c.id = a.chat_id
    where a.resolved_at is null and (c.org_id = p_org or a.target_user in (select user_id from memberships where org_id = p_org and status = 'active'))
    order by a.created_at;
end $$;

-- Решение по жалобе: скрыть сообщение (удаляется) и/или исключить из организации.
create function coord_resolve_abuse(p_org uuid, p_id bigint, p_delete_message boolean, p_remove_user boolean) returns void
language plpgsql security definer set search_path = public as $$
declare a abuse_reports;
begin
  perform assert_coordinator(p_org);
  select * into a from abuse_reports where id = p_id;
  if p_delete_message and a.message_id is not null then delete from messages where id = a.message_id; end if;
  if p_remove_user and a.target_user is not null then perform coord_remove_member(p_org, a.target_user); end if;
  update abuse_reports set resolved_at = now() where id = p_id;
end $$;

-- Мои организации, где я координатор (для выбора в кабинете).
create function coord_orgs() returns table (id uuid, name text)
language sql stable security definer set search_path = public as $$
  select o.id, o.name from organizations o join memberships m on m.org_id = o.id
  where m.user_id = auth.uid() and m.status = 'active' and m.role = 'coordinator' order by o.name
$$;
