-- Сценарии на локальной базе: psql -v ON_ERROR_STOP=1 -f 00_local_supabase_stub.sql -f ../migrations/*.sql -f 10_scenarios.sql
\set ON_ERROR_STOP 1
set client_min_messages = warning;

-- Пользователи
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000c1', 'coord@tq.kz'),
  ('00000000-0000-0000-0000-0000000000a1', 'senior@tq.kz'),
  ('00000000-0000-0000-0000-0000000000b1', 'aigerim@mail.kz'),
  ('00000000-0000-0000-0000-0000000000b2', 'aruzhan@mail.kz'),
  ('00000000-0000-0000-0000-0000000000b3', 'timur@mail.kz'),
  ('00000000-0000-0000-0000-0000000000b4', 'dana@mail.kz');
insert into profiles (id, name, birth_year) values
  ('00000000-0000-0000-0000-0000000000c1', 'Айжан Б.', 1990),
  ('00000000-0000-0000-0000-0000000000a1', 'Арман Т.', 1999),
  ('00000000-0000-0000-0000-0000000000b1', 'Айгерим Н.', 2000),
  ('00000000-0000-0000-0000-0000000000b2', 'Аружан М.', 2011),   -- до 18
  ('00000000-0000-0000-0000-0000000000b3', 'Тимур К.', 1998),
  ('00000000-0000-0000-0000-0000000000b4', 'Дана С.', 2001);
insert into organizations (id, name, type, city, lat, lng, verified, invite_code) values
  ('00000000-0000-0000-0000-00000000000f', 'TazaQala', 'ecology', 'astana', 51.128, 71.430, true, 'TAZA2026');
insert into memberships (user_id, org_id, status, role) values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000000f', 'active', 'coordinator'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-00000000000f', 'active', 'senior');
-- Квест «сейчас» на 3 места (одна команда) и пересекающийся по времени
insert into quests (id, org_id, title, starts_at, duration_min, lat, lng, capacity) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-00000000000f', 'Уборка набережной', now() - interval '10 minutes', 180, 51.1253, 71.4370, 3),
  ('00000000-0000-0000-0000-0000000000e2', '00000000-0000-0000-0000-00000000000f', 'Сбор пластика', now() + interval '1 hour', 120, 51.115, 71.456, 20);
update teams set senior_id = '00000000-0000-0000-0000-0000000000a1' where quest_id = '00000000-0000-0000-0000-0000000000e1';

create or replace function pg_temp.expect_error(sql text, needle text) returns void language plpgsql as $$
begin
  execute sql;
  raise exception 'ожидалась ошибка «%», но её не было: %', needle, sql;
exception when others then
  if sqlerrm not like '%' || needle || '%' then raise exception 'ожидалась «%», получено «%»', needle, sqlerrm; end if;
end $$;

do $$ begin assert (select count(*) from teams where quest_id = '00000000-0000-0000-0000-0000000000e2') = 2, 'команды по 10: 20 мест → 2 команды'; end $$;
do $$ begin assert (select count(*) from chats where kind = 'channel') = 1, 'канал организации создан'; end $$;

set role authenticated;

-- 1. Вступление: заявка → координатор одобряет
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select pg_temp.expect_error($$select request_join(null, 'WRONG1')$$, 'invalid_code');
do $$ begin assert request_join(null, 'taza2026') = 'pending'; end $$;
select pg_temp.expect_error($$select join_quest('00000000-0000-0000-0000-0000000000e1')$$, 'not_member');
select pg_temp.expect_error($$select invite_code from organizations$$, 'permission denied');
do $$ begin assert (select count(*) from organizations) = 1, 'организации видны'; end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b3', false);
select pg_temp.expect_error($$select decide_membership('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-00000000000f', true)$$, 'forbidden');
do $$ begin assert (select count(*) from memberships) = 0, 'чужие заявки не видны'; end $$;

select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
select decide_membership(u, '00000000-0000-0000-0000-00000000000f', true)
  from (values ('00000000-0000-0000-0000-0000000000b1'::uuid)) v(u);
reset role;
insert into memberships (user_id, org_id, status) select u::uuid, '00000000-0000-0000-0000-00000000000f', 'active'
  from unnest(array['00000000-0000-0000-0000-0000000000b2', '00000000-0000-0000-0000-0000000000b3', '00000000-0000-0000-0000-0000000000b4']) u;
set role authenticated;

-- 2. Запись: места, лист ожидания, пересечение по времени
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
do $$ begin assert (join_quest('00000000-0000-0000-0000-0000000000e1')).status = 'joined'; end $$;
select pg_temp.expect_error($$select join_quest('00000000-0000-0000-0000-0000000000e1')$$, 'already_signed');
select pg_temp.expect_error($$select join_quest('00000000-0000-0000-0000-0000000000e2')$$, 'time_conflict');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
do $$ begin assert (join_quest('00000000-0000-0000-0000-0000000000e1')).status = 'joined'; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b3', false);
do $$ begin assert (join_quest('00000000-0000-0000-0000-0000000000e1')).status = 'joined'; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b4', false);
do $$ declare s signups; begin s := join_quest('00000000-0000-0000-0000-0000000000e1'); assert s.status = 'waitlist' and s.waitlist_pos = 1, 'мест нет → лист ожидания №1'; end $$;
do $$ begin assert (select joined from team_counts('00000000-0000-0000-0000-0000000000e1')) = 3; end $$;

-- 3. Тимур отменяет — место получает Дана из листа ожидания
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b3', false);
select leave_quest('00000000-0000-0000-0000-0000000000e1');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b4', false);
do $$ begin assert (select status from signups where user_id = auth.uid() and quest_id = '00000000-0000-0000-0000-0000000000e1' and status <> 'cancelled') = 'joined', 'место перешло из листа ожидания'; end $$;
do $$ begin assert exists (select 1 from notifications where kind = 'waitlist_promoted'), 'уведомление о месте'; end $$;
do $$ begin assert exists (select 1 from chat_members cm join chats c on c.id = cm.chat_id where c.kind = 'team' and cm.user_id = auth.uid()), 'добавлена в чат команды'; end $$;

-- 4. Отметки: рядом (геометка), далеко (без геометки), из «будущего» — нельзя
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
do $$ begin assert (check_in('00000000-0000-0000-0000-0000000000e1', 51.1260, 71.4372)).geo_verified, 'в 80 м — геометка'; end $$;
do $$ begin assert (check_in('00000000-0000-0000-0000-0000000000e1', 51.1260, 71.4372)).geo_verified, 'повтор из очереди — без ошибки'; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b4', false);
select pg_temp.expect_error($$select check_in('00000000-0000-0000-0000-0000000000e1', 51.1260, 71.4372, now() + interval '1 hour')$$, 'bad_time');
do $$ begin assert not (check_in('00000000-0000-0000-0000-0000000000e1', 51.20, 71.50)).geo_verified, '10 км — без геометки'; end $$;
-- Аружан не отметилась: старший отметит вручную
select pg_temp.expect_error($$select mark_present('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000b2', true)$$, 'not_senior');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select mark_present('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000b2', true);
do $$ begin assert (select count(*) from signups where quest_id = '00000000-0000-0000-0000-0000000000e1' and status = 'joined') = 3, 'старший видит свою команду'; end $$;

-- 5. Закрытие смены: часы не больше длительности (3 ч), шаг 0,5; ручная отметка помечена
do $$ declare r shift_reports; begin
  r := close_shift('00000000-0000-0000-0000-0000000000e1', jsonb_build_object('00000000-0000-0000-0000-0000000000b1', 9, '00000000-0000-0000-0000-0000000000b4', 2.3));
  assert (select hours from shift_report_items where report_id = r.id and user_id = '00000000-0000-0000-0000-0000000000b1') = 3.0, 'завысить нельзя';
  assert (select hours from shift_report_items where report_id = r.id and user_id = '00000000-0000-0000-0000-0000000000b4') = 2.5, 'шаг 0,5';
  assert (select manual from shift_report_items where report_id = r.id and user_id = '00000000-0000-0000-0000-0000000000b2'), 'ручная отметка помечена';
end $$;
select pg_temp.expect_error($$select mark_present('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000000b2', false)$$, 'already_closed');

-- 6. Подтверждение: волонтёр не может, координатор — да; начисления и бонус старшему
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select pg_temp.expect_error($$select approve_shift((select id from shift_reports limit 1), true)$$, 'not_pending');
select pg_temp.expect_error($$insert into credits (user_id, kind, tz, quest_title, org_name, shift_date) values (auth.uid(), 'shift', 999, 'x', 'x', now())$$, 'permission denied');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
select approve_shift((select id from shift_reports limit 1), true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
do $$ begin assert (select hours from my_totals) = 3 and (select tz from my_totals) = 15, '3 ч = 15 Tz'; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
do $$ begin assert (select tz from my_totals) = 10, 'бонус старшему +10 Tz'; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
select penalize((select id from shift_reports limit 1), 5, 'Аружан не было на месте');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
do $$ begin assert (select tz from my_totals) = 5, 'штраф −5 Tz'; end $$;

-- 7. Видимость: часы взрослого видны всем, часы подростка — только друзьям
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b3', false);
do $$ begin assert (select hours from person_card('00000000-0000-0000-0000-0000000000b1')) = 3, 'часы взрослого видны'; end $$;
do $$ begin assert (select hours from person_card('00000000-0000-0000-0000-0000000000b2')) is null, 'часы подростка скрыты от не-друзей'; end $$;
do $$ begin assert (select count(*) from profiles) = 1, 'чужие профили напрямую не читаются'; end $$;
do $$ begin assert exists (select 1 from search_people('айг') where name = 'Айгерим Н.'), 'поиск по началу имени'; end $$;
do $$ begin assert exists (select 1 from search_people('кай') where name = 'Тимур К.') is false; end $$;

-- 8. Дружба: заявка → встречное согласие; личный чат только с друзьями
select pg_temp.expect_error($$select open_direct_chat('00000000-0000-0000-0000-0000000000b2')$$, 'not_friends');
do $$ begin assert send_friend_request('00000000-0000-0000-0000-0000000000b2') = 'pending'; end $$;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
select respond_friend_request('00000000-0000-0000-0000-0000000000b3', true);
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b3', false);
do $$ begin assert (select hours from person_card('00000000-0000-0000-0000-0000000000b2')) = 3, 'другу часы подростка видны'; end $$;
do $$ declare c uuid; begin c := open_direct_chat('00000000-0000-0000-0000-0000000000b2');
  insert into messages (chat_id, author_id, body) values (c, auth.uid(), 'Привет!'); end $$;

-- 9. Канал: пишет только координатор
select pg_temp.expect_error($$insert into messages (chat_id, author_id, body) select id, auth.uid(), 'x' from chats where kind = 'channel'$$, 'row-level security');

-- 10. Блокировка: дружба исчезает, сообщения скрыты
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b2', false);
insert into blocks (blocker, blocked) values (auth.uid(), '00000000-0000-0000-0000-0000000000b3');
do $$ begin assert not are_friends(auth.uid(), '00000000-0000-0000-0000-0000000000b3'), 'блокировка удаляет дружбу'; end $$;
do $$ begin assert (select count(*) from messages m join chats c on c.id = m.chat_id where c.kind = 'direct') = 0, 'сообщения заблокированного скрыты'; end $$;

-- 11. Рейтинг месяца: я всегда есть, подросток не виден чужим
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b4', false);
do $$ begin
  assert exists (select 1 from month_rating('00000000-0000-0000-0000-00000000000f') where is_me), 'я в рейтинге';
  assert not exists (select 1 from month_rating('00000000-0000-0000-0000-00000000000f') where name = 'Аружан М.'), 'подросток скрыт';
  assert (select place from month_rating('00000000-0000-0000-0000-00000000000f') where name = 'Айгерим Н.') = 1;
end $$;

-- 12. Портфолио: проверка без входа, отзыв номера
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select set_config('test.code', my_portfolio_code(), false);
do $$ begin assert my_portfolio_code() ~ '^TN[A-HJ-NP-Z2-9]{6}$', 'формат номера'; end $$;
reset role; set role anon; select set_config('request.jwt.claim.sub', '', false);
do $$ begin assert (select hours from verify_portfolio(current_setting('test.code'))) = 3, 'проверка по номеру без входа'; end $$;
select pg_temp.expect_error($$select * from credits$$, 'permission denied');
reset role; set role authenticated; select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select my_portfolio_code(true);
reset role; set role anon;
do $$ begin assert not exists (select 1 from verify_portfolio(current_setting('test.code'))), 'старый номер отозван'; end $$;

-- 13. Год рождения менять нельзя; удаление: через 30 дней профиль удаляется, часы остаются без имени
reset role; set role authenticated; select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b1', false);
select pg_temp.expect_error($$update profiles set birth_year = 1990 where id = auth.uid()$$, 'birth_year_locked');
select request_account_deletion();
reset role;
update profiles set deletion_requested_at = now() - interval '31 days' where id = '00000000-0000-0000-0000-0000000000b1';
do $$ begin assert purge_deleted_accounts() = 1; end $$;
do $$ begin assert (select count(*) from credits where user_id is null and kind = 'shift' and hours = 3) = 1, 'часы остались без имени'; end $$;

select 'ВСЕ СЦЕНАРИИ ПРОЙДЕНЫ' as result;
