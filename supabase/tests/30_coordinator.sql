-- После 10_scenarios.sql на той же базе.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b3', false);
select pg_temp.expect_error($$select * from coord_overview('00000000-0000-0000-0000-00000000000f')$$, 'forbidden');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
do $$ begin
  assert (select count(*) from coord_orgs()) = 1;
  assert (select members from coord_overview('00000000-0000-0000-0000-00000000000f')) >= 3;
  assert (select count(*) from coord_members('00000000-0000-0000-0000-00000000000f') where minor) = 1, 'подросток помечен';
  assert (select count(*) from coord_reports('00000000-0000-0000-0000-00000000000f', 'approved')) = 1;
  assert (select manual from coord_reports('00000000-0000-0000-0000-00000000000f', 'approved')) = 1, 'ручных отметок: 1';
  assert (select count(*) from coord_report_items((select id from shift_reports limit 1)) where manual) = 1;
  assert (select jsonb_array_length(teams) from coord_quests('00000000-0000-0000-0000-00000000000f') where title = 'Сбор пластика') = 2;
end $$;
select coord_set_role('00000000-0000-0000-0000-00000000000f', '00000000-0000-0000-0000-0000000000b4', 'senior');
select coord_assign_senior((select id from teams t where quest_id = '00000000-0000-0000-0000-0000000000e2' and number = 1), '00000000-0000-0000-0000-0000000000b4');
select pg_temp.expect_error($$select coord_assign_senior((select id from teams t where quest_id = '00000000-0000-0000-0000-0000000000e2' and number = 2), '00000000-0000-0000-0000-0000000000b2')$$, 'not_senior');
do $$ begin assert coord_invite_code('00000000-0000-0000-0000-00000000000f') = 'TAZA2026'; assert coord_invite_code('00000000-0000-0000-0000-00000000000f', true) ~ '^[A-HJ-NP-Z2-9]{8}$', 'новый код'; end $$;
select coord_post('00000000-0000-0000-0000-00000000000f', 'В субботу большой субботник!');
do $$ begin assert exists (select 1 from messages m join chats c on c.id = m.chat_id where c.kind = 'channel'); end $$;
-- Жалоба и решение
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000b4', false);
insert into abuse_reports (reporter, target_user, reason) values (auth.uid(), '00000000-0000-0000-0000-0000000000b3', 'insult');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000c1', false);
do $$ begin assert (select open_abuse from coord_overview('00000000-0000-0000-0000-00000000000f')) = 1; end $$;
select coord_resolve_abuse('00000000-0000-0000-0000-00000000000f', (select id from coord_abuse('00000000-0000-0000-0000-00000000000f')), false, true);
do $$ begin assert (select count(*) from coord_members('00000000-0000-0000-0000-00000000000f') where name = 'Тимур К.') = 0, 'исключён'; end $$;
select coord_cancel_quest('00000000-0000-0000-0000-0000000000e2');
do $$ begin assert (select status from coord_quests('00000000-0000-0000-0000-00000000000f') where title = 'Сбор пластика') = 'cancelled'; end $$;
select 'КАБИНЕТ КООРДИНАТОРА: ВСЁ ВЕРНО' as result;
