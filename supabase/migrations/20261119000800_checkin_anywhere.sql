-- Квесты, где отметка не проверяет расстояние: онлайн-акции и тестовая организация
-- для проверяющих App Store / Google Play (они находятся не в Казахстане).
-- Включает только администратор через SQL; часы всё равно подтверждает старший и координатор.
alter table quests add column checkin_anywhere boolean not null default false;

drop function quest_list(uuid, text);
create function quest_list(p_org uuid default null, p_city text default 'astana')
returns table (id uuid, org_id uuid, org_name text, title text, description text, difficulty difficulty, starts_at timestamptz,
               duration_min int, lat double precision, lng double precision, address text, capacity int, joined bigint, senior_name text,
               checkin_anywhere boolean)
language sql stable security definer set search_path = public as $$
  select q.id, q.org_id, o.name, q.title, q.description, q.difficulty, q.starts_at, q.duration_min, q.lat, q.lng, q.address, q.capacity,
         (select count(*) from signups s where s.quest_id = q.id and s.status = 'joined'),
         (select p.name from teams t join profiles p on p.id = t.senior_id where t.quest_id = q.id order by t.number limit 1),
         q.checkin_anywhere
  from quests q join organizations o on o.id = q.org_id
  where q.status = 'published' and shift_end(q) > now()
    and (p_org is null and o.city = p_city or q.org_id = p_org)
  order by q.starts_at
$$;

create or replace function check_in(p_quest uuid, p_lat double precision, p_lng double precision, p_at timestamptz default now())
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
    values (s.id, p_at, p_lat, p_lng, d, q.checkin_anywhere or coalesce(d <= 300, false))
    on conflict (signup_id) do nothing returning * into c;
  if c is null then select * into c from check_ins where signup_id = s.id; end if;  -- повтор из очереди — без ошибки
  return c;
end $$;

-- Координатор не может сам включить отметку без геолокации — только администратор (service_role / SQL).
create function quests_lock_checkin_anywhere() returns trigger language plpgsql as $$
begin
  if current_user in ('authenticated', 'anon')
     and new.checkin_anywhere is distinct from (case when tg_op = 'INSERT' then false else old.checkin_anywhere end) then
    raise exception 'forbidden';
  end if;
  return new;
end $$;
create trigger quests_checkin_anywhere before insert or update on quests
  for each row execute function quests_lock_checkin_anywhere();

-- Первая версия в магазинах — 1.0.0 (иначе приложение сразу потребует обновиться).
update app_config set value = '"1.0.0"' where key in ('min_version', 'latest_version');
