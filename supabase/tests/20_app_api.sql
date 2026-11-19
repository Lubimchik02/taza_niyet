\set ON_ERROR_STOP 1
set client_min_messages = warning;
insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000d1'), ('00000000-0000-0000-0000-0000000000d2');
insert into profiles (id, name, birth_year) values ('00000000-0000-0000-0000-0000000000d1', 'Ержан А.', 1995), ('00000000-0000-0000-0000-0000000000d2', 'Мира О.', 1997);
update teams set senior_id = '00000000-0000-0000-0000-0000000000d2' where quest_id = (select id from quests where title = 'Полив саженцев');
insert into memberships (user_id, org_id, status, role) values ('00000000-0000-0000-0000-0000000000d2', md5('ze')::uuid, 'active', 'senior');
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
do $$ begin assert (select count(*) from org_list()) = 6; assert (select count(*) from quest_list()) = 18, 'без организации — все квесты города'; end $$;
do $$ begin assert request_join(null, 'ZHASYL') = 'pending'; assert (select status from my_membership()) = 'pending'; end $$;
reset role; update memberships set status = 'active' where user_id = '00000000-0000-0000-0000-0000000000d1'; set role authenticated;
do $$ begin assert (select count(*) from quest_list(md5('ze')::uuid)) = 3, 'своя организация'; end $$;
do $$ declare q uuid := (select id from quest_list(md5('ze')::uuid) where title = 'Полив саженцев'); begin
  perform join_quest(q);
  assert (select team_number from my_signups() where quest_id = q) = 1;
  assert (select senior_name from my_signups() where quest_id = q) = 'Мира О.';
  perform set_config('test.chat', chat_id_for('team-' || (select team_id from my_signups() where quest_id = q))::text, false);
end $$;
insert into messages (chat_id, author_id, body) values (current_setting('test.chat')::uuid, auth.uid(), 'Буду вовремя');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
do $$ begin assert (select count(*) from team_roster((select id from quests where title = 'Полив саженцев'))) = 1, 'старший видит команду'; end $$;
reset role;
-- Старший ещё не в чате команды (добавляется при назначении) — уведомлений о сообщении нет; добавим и проверим
insert into chat_members (chat_id, user_id) values (current_setting('test.chat')::uuid, '00000000-0000-0000-0000-0000000000d2');
set role authenticated; select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d1', false);
insert into messages (chat_id, author_id, body, client_id) values (current_setting('test.chat')::uuid, auth.uid(), 'Я на месте', 'c1');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000d2', false);
do $$ begin assert exists (select 1 from notifications where kind = 'chat' and route like '/chat/team-%'), 'уведомление о сообщении'; end $$;
select register_push_token('tok-123', 'android');
do $$ begin assert (select count(*) from push_tokens) = 1; end $$;
select 'API ПРИЛОЖЕНИЯ: ВСЁ ВЕРНО' as result;
