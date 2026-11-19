-- Taza Niyet — права доступа (RLS). По умолчанию всё закрыто; открываем ровно нужное.
-- Изменения часов, мест и отметок — только через функции (security definer), прямой записи нет.

alter table profiles enable row level security;
alter table organizations enable row level security;
alter table memberships enable row level security;
alter table quests enable row level security;
alter table teams enable row level security;
alter table signups enable row level security;
alter table check_ins enable row level security;
alter table shift_reports enable row level security;
alter table shift_report_items enable row level security;
alter table credits enable row level security;
alter table friendships enable row level security;
alter table blocks enable row level security;
alter table chats enable row level security;
alter table chat_members enable row level security;
alter table messages enable row level security;
alter table abuse_reports enable row level security;
alter table notifications enable row level security;
alter table push_tokens enable row level security;
alter table app_config enable row level security;
alter table portfolio_tokens enable row level security;

-- Профиль: свой — читать и менять (кроме года рождения — он влияет на правила для младше 18).
create policy "свой профиль" on profiles for select to authenticated using (id = auth.uid());
create policy "создать свой профиль" on profiles for insert to authenticated with check (id = auth.uid());
create policy "изменить свой профиль" on profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());
create function profiles_lock_birth_year() returns trigger language plpgsql as $$
begin
  if new.birth_year <> old.birth_year and current_user = 'authenticated' then raise exception 'birth_year_locked'; end if;
  return new;
end $$;
create trigger profiles_birth_year before update on profiles for each row execute function profiles_lock_birth_year();
-- Чужие профили — через search_people / month_rating / person_card (только безопасные поля).
create function person_card(p_user uuid)
returns table (id uuid, name text, org_name text, minor boolean, hours numeric, tz bigint, shifts bigint, is_friend boolean, request_from_me boolean, request_to_me boolean)
language sql stable security definer set search_path = public as $$
  select p.id, p.name, o.name, is_minor(p.birth_year),
         case when can_see_hours(p.id) then (select coalesce(sum(hours), 0) from credits where user_id = p.id) end,
         case when can_see_hours(p.id) then (select coalesce(sum(tz), 0) from credits where user_id = p.id) end,
         case when can_see_hours(p.id) then (select count(*) from credits where user_id = p.id and kind = 'shift') end,
         are_friends(p.id, auth.uid()),
         exists (select 1 from friendships f where f.user_a = least(p.id, auth.uid()) and f.user_b = greatest(p.id, auth.uid()) and f.status = 'pending' and f.requested_by = auth.uid()),
         exists (select 1 from friendships f where f.user_a = least(p.id, auth.uid()) and f.user_b = greatest(p.id, auth.uid()) and f.status = 'pending' and f.requested_by = p.id)
  from profiles p
  left join memberships m on m.user_id = p.id and m.status = 'active'
  left join organizations o on o.id = m.org_id
  where p.id = p_user and not is_blocked(p.id, auth.uid()) and p.deletion_requested_at is null
$$;

-- Организации видны всем вошедшим; код приглашения — только координатору (через отдельную функцию).
create policy "организации видны" on organizations for select to authenticated using (true);
create function org_invite_code(p_org uuid) returns text language sql stable security definer set search_path = public as $$
  select invite_code from organizations where id = p_org and is_coordinator(p_org)
$$;

create policy "своё членство или координатор" on memberships for select to authenticated
  using (user_id = auth.uid() or is_coordinator(org_id));
create policy "выйти из организации" on memberships for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid() and status = 'left' and role = 'volunteer');
create policy "координатор назначает старших" on memberships for update to authenticated
  using (is_coordinator(org_id)) with check (is_coordinator(org_id) and status = 'active');

-- Квесты: опубликованные видят все вошедшие (без организации — только смотреть); пишет координатор.
create policy "квесты видны" on quests for select to authenticated using (status = 'published' or is_coordinator(org_id));
create policy "координатор создаёт квесты" on quests for insert to authenticated with check (is_coordinator(org_id) and created_by = auth.uid());
create policy "координатор меняет квесты" on quests for update to authenticated using (is_coordinator(org_id)) with check (is_coordinator(org_id));

create policy "команды видны" on teams for select to authenticated using (true);
create policy "старший команды" on teams for update to authenticated
  using (is_coordinator((select org_id from quests where id = quest_id)))
  with check (senior_id is null or exists (select 1 from memberships m join quests q on q.org_id = m.org_id
    where q.id = quest_id and m.user_id = senior_id and m.status = 'active' and m.role in ('senior', 'coordinator')));

-- Записи: свои; старший — своей команды; координатор — своей организации.
create policy "записи" on signups for select to authenticated using (
  user_id = auth.uid()
  or team_id in (select id from teams where senior_id = auth.uid())
  or is_coordinator((select org_id from quests where id = quest_id)));
-- Сколько занято мест — без личных данных.
create function team_counts(p_quest uuid) returns table (team_id uuid, joined bigint, capacity int, number int, senior_name text)
language sql stable security definer set search_path = public as $$
  select t.id, (select count(*) from signups s where s.team_id = t.id and s.status = 'joined'), t.capacity, t.number, p.name
  from teams t left join profiles p on p.id = t.senior_id where t.quest_id = p_quest order by t.number
$$;

create policy "отметки" on check_ins for select to authenticated using (
  exists (select 1 from signups s where s.id = signup_id and (s.user_id = auth.uid()
    or s.team_id in (select id from teams where senior_id = auth.uid())
    or is_coordinator((select org_id from quests where id = s.quest_id)))));

create policy "отчёты смен" on shift_reports for select to authenticated using (
  senior_id = auth.uid() or is_coordinator((select org_id from quests where id = quest_id)));
create policy "строки отчётов" on shift_report_items for select to authenticated using (
  user_id = auth.uid() or exists (select 1 from shift_reports r where r.id = report_id
    and (r.senior_id = auth.uid() or is_coordinator((select org_id from quests where id = r.quest_id)))));

-- Начисления: свои и своей организации (для координатора). Вставка — только функциями.
create policy "начисления" on credits for select to authenticated using (user_id = auth.uid() or is_coordinator(org_id));

create policy "мои дружбы" on friendships for select to authenticated using (auth.uid() in (user_a, user_b));
create policy "удалить из друзей" on friendships for delete to authenticated using (auth.uid() in (user_a, user_b));

create policy "мои блокировки" on blocks for select to authenticated using (blocker = auth.uid());
create policy "заблокировать" on blocks for insert to authenticated with check (blocker = auth.uid() and blocked <> auth.uid());
create policy "разблокировать" on blocks for delete to authenticated using (blocker = auth.uid());
create function block_cleanup() returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from friendships where user_a = least(new.blocker, new.blocked) and user_b = greatest(new.blocker, new.blocked);
  return new;
end $$;
create trigger blocks_cleanup after insert on blocks for each row execute function block_cleanup();

-- Чаты: только участник. Писать в канал — только координатор; в личный — если нет блокировки.
create function is_member(p_chat uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from chat_members where chat_id = p_chat and user_id = auth.uid())
$$;
create policy "мои чаты" on chats for select to authenticated using (is_member(id));
create policy "участники моих чатов" on chat_members for select to authenticated using (is_member(chat_id));
create policy "без звука и прочитано" on chat_members for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "читать сообщения" on messages for select to authenticated using (is_member(chat_id)
  and (author_id is null or not exists (select 1 from blocks where blocker = auth.uid() and blocked = author_id)));
create policy "писать сообщения" on messages for insert to authenticated with check (
  author_id = auth.uid() and is_member(chat_id) and (
    select case c.kind
      when 'channel' then is_coordinator(c.org_id)
      when 'direct' then not exists (select 1 from chat_members cm where cm.chat_id = c.id and cm.user_id <> auth.uid() and is_blocked(cm.user_id, auth.uid()))
      else true end
    from chats c where c.id = chat_id));

create policy "пожаловаться" on abuse_reports for insert to authenticated with check (reporter = auth.uid());

create policy "мои уведомления" on notifications for select to authenticated using (user_id = auth.uid());
create policy "прочитать уведомление" on notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "мои устройства" on push_tokens for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Конфигурация (версии, флаги) видна всем, даже до входа — нужна для экрана обновления.
create policy "конфигурация видна" on app_config for select to anon, authenticated using (true);

-- ---------- Права на объекты ----------
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant select on app_config to anon;
-- Код приглашения скрыт: читаются все поля организации, кроме invite_code.
revoke select on organizations from authenticated;
grant select (id, name, type, city, lat, lng, verified, accepts_new, created_at) on organizations to authenticated;
revoke insert, update, delete on credits, check_ins, shift_reports, shift_report_items, signups, notifications, chats, chat_members, portfolio_tokens, app_config, organizations, teams from authenticated;
grant update (muted, last_read_at) on chat_members to authenticated;
grant update (read_at) on notifications to authenticated;
grant update (senior_id) on teams to authenticated;
grant update (status, role) on memberships to authenticated;
revoke insert, delete on memberships from authenticated;
revoke all on function purge_deleted_accounts() from public, anon, authenticated;
grant execute on function verify_portfolio(text) to anon;
grant select on my_totals to authenticated;
