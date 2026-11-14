-- Founder dashboard (migration 20261117000000). Runs after v4_test.sql.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
reset role;
-- set as the service key would (test answer, not the real one)
set role service_role;
select public.set_admin_secret('eve@pride.hofstra.edu', 'Favourite test word?', '  Banana ');
reset role;

set role authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');   -- Ivy: not the founder
select tests.fails($$select public.admin_question()$$, 'forbidden|');
select tests.fails($$select public.founder_overview()$$, 'forbidden|');
select tests.fails($$select public.set_admin_secret('ivy@pride.hofstra.edu', 'q?????', 'x')$$, 'permission denied');
select tests.fails('select * from public.admin_secrets', 'permission denied');

select tests.as_user('00000000-0000-0000-0000-0000000000e1');   -- Eve: founder
do $$ begin assert public.admin_question() = 'Favourite test word?'; end $$;
select tests.fails($$select public.founder_overview()$$, 'forbidden|Answer your security question');
do $$ begin
  assert public.admin_unlock('apple') is null, 'wrong answer does not unlock';
  assert public.admin_unlock('BANANA') is not null, 'answer is case/space-insensitive';
  assert (public.founder_overview() -> 'totals' ->> 'students')::int >= 6;
  assert jsonb_array_length(public.founder_overview() -> 'clubs') >= 4;
  assert jsonb_array_length(public.founder_overview() -> 'signups_by_day') = 30;
end $$;
select public.founder_lock();
select tests.fails($$select public.founder_overview()$$, 'forbidden|');
-- brute force is throttled
do $$ begin for i in 1..5 loop perform public.admin_unlock('nope'); end loop; end $$;
select tests.fails($$select public.admin_unlock('banana')$$, 'validation|Too many tries');
reset role;
do $$ begin assert (select answer_hash not like '%banana%' from public.admin_secrets limit 1), 'only a hash is stored'; end $$;
-- publishing from the dashboard: founder only, unlocked only, and still needs all four officers
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
select tests.fails($$select public.founder_set_published('10000000-0000-0000-0000-000000000003', true)$$, 'forbidden|');
reset role;
delete from public.admin_attempts;
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000e1');
select tests.fails($$select public.founder_set_published('10000000-0000-0000-0000-000000000003', true)$$, 'forbidden|');
do $$ begin assert public.admin_unlock('banana') is not null; end $$;
select tests.fails($$select public.founder_set_published('10000000-0000-0000-0000-000000000003', true)$$, 'validation|A club needs');
-- Robotics Guild lost its secretary in v3_test (3/4 officers): unpublishing works, republishing is refused.
select public.founder_set_published((select id from public.clubs where name = 'Robotics Guild'), false);
select tests.fails($$select public.founder_set_published((select id from public.clubs where name = 'Robotics Guild'), true)$$, 'validation|A club needs');
reset role;
\echo 'ALL V5 TESTS PASSED'
