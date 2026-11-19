\set ON_ERROR_STOP 1
-- После seed.sql и 20_app_api.sql: d1 — активный участник «Жасыл Ел».
set client_min_messages = warning;
reset role;
insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000e1');
insert into profiles (id, name, birth_year) values ('00000000-0000-0000-0000-0000000000e1', 'Координатор', 1990);
insert into memberships (user_id, org_id, status, role) values ('00000000-0000-0000-0000-0000000000e1', md5('ze')::uuid, 'active', 'coordinator');
-- Администратор (не authenticated) создаёт квест для проверяющих: начинается сейчас, отметка без геолокации.
insert into quests (org_id, title, starts_at, duration_min, lat, lng, capacity, checkin_anywhere)
  values (md5('ze')::uuid, 'App Review: уборка', now() - interval '10 minutes', 120, 51.09, 71.39, 10, true);
insert into quests (org_id, title, starts_at, duration_min, lat, lng, capacity)
  values (md5('ze')::uuid, 'Обычный квест сейчас', now() - interval '10 minutes', 120, 51.09, 71.39, 10);

set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
do $$ begin
  assert (select checkin_anywhere from quest_list(md5('ze')::uuid) where title = 'App Review: уборка'), 'флаг виден приложению';
  assert not (select checkin_anywhere from quest_list(md5('ze')::uuid) where title = 'Обычный квест сейчас');
end $$;
do $$ declare a uuid := (select id from quests where title = 'App Review: уборка');
             b uuid := (select id from quests where title = 'Обычный квест сейчас'); begin
  perform join_quest(a);
  -- проверяющий в Калифорнии
  assert (check_in(a, 37.33, -122.03)).geo_verified, 'без проверки расстояния — подтверждено';
  perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
  perform join_quest(b);
  assert not (check_in(b, 37.33, -122.03)).geo_verified, 'обычный квест — далеко, не подтверждено';
end $$;

-- Координатор не может включить флаг сам.
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', false);
do $$ begin
  begin
    update quests set checkin_anywhere = true where title = 'Обычный квест сейчас';
    assert false, 'координатор не должен менять флаг';
  exception when raise_exception then assert sqlerrm = 'forbidden'; end;
  update quests set description = 'Берите перчатки' where title = 'App Review: уборка';  -- остальные поля можно
  begin
    insert into quests (org_id, title, starts_at, duration_min, lat, lng, capacity, created_by, checkin_anywhere)
      values (md5('ze')::uuid, 'Хитрый квест', now(), 60, 51, 71, 5, auth.uid(), true);
    assert false, 'и создать с флагом тоже нельзя';
  exception when raise_exception then assert sqlerrm = 'forbidden'; end;
end $$;
reset role;
do $$ begin assert (select value #>> '{}' from app_config where key = 'min_version') = '1.0.0', 'первая версия 1.0.0'; end $$;
select 'ОТМЕТКА БЕЗ ГЕОЛОКАЦИИ: ВСЁ ВЕРНО' as result;
