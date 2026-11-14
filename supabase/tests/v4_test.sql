-- Tests for migration 20261116000000 (honest rating copy). Runs after v3_test.sql.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
reset role;
do $$ begin
  assert not exists (select 1 from public.notifications where body ilike '%anonymous%'), 'no notification may claim anonymity';
  assert pg_get_functiondef('public.send_due_notifications()'::regprocedure) not ilike '%anonymous%', 'scheduler text must not claim anonymity';
end $$;
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
select tests.fails($$select public.send_due_notifications()$$, 'permission denied');
reset role;
\echo 'ALL V4 TESTS PASSED'
