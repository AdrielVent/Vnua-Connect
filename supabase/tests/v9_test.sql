-- Event perks (migration 20261119000000). Runs after v8_test.sql.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
create temp table t_rg as select id from public.clubs where name = 'Robotics Guild';
grant select on t_rg to anon, authenticated;
reset role;
update public.clubs set is_published = false where id = (select id from t_rg);
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000e1');   -- Eve, president
create temp table t_pe as select public.create_event(array[(select id from t_rg)], 'Pizza and pitches', now() + interval '4 days', 60, 'Weed 120', '',
  gen_random_uuid(), '{1440}', '{}', array['food', 'swag', 'food', 'free money']) as id;
grant select on t_pe to authenticated;
do $$ begin
  assert (select perks from public.events where id = (select id from t_pe)) = array['food', 'swag'], 'unknown perks dropped, duplicates removed';
end $$;
select public.update_event((select id from t_pe), 'Pizza and pitches', (select starts_at from public.events where id = (select id from t_pe)), 60, 'Weed 120', '', '{1440}', '{}', array['resources', 'beginners']);
do $$ begin assert (select perks from public.events where id = (select id from t_pe)) = array['beginners', 'resources']; end $$;
-- the old 7-argument call (iOS app, schedule_poll) still works and means "no perks"
create temp table t_pe2 as select public.create_event(array[(select id from t_rg)], 'Plain meeting', now() + interval '5 days', 60, '', '', gen_random_uuid()) as id;
do $$ begin assert (select perks from public.events where id = (select id from t_pe2)) = '{}'; end $$;
reset role;
\echo 'ALL V9 TESTS PASSED'
