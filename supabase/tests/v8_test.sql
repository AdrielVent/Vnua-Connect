-- Archive / delete clubs (migration 20261118030000). Runs after v7_test.sql.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
create temp table t_rg as select id from public.clubs where name = 'Robotics Guild';
grant select on t_rg to anon, authenticated;
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000f1');   -- Finn: VP of Robotics, not president
select tests.fails($$select public.archive_club((select id from t_rg), true)$$, 'forbidden|Only the club''s president');
select tests.as_user('00000000-0000-0000-0000-0000000000e1');   -- Eve: president
select tests.fails($$select public.delete_club((select id from t_rg), 'Robotics Guild')$$, 'validation|People have checked in');
select public.archive_club((select id from t_rg), true);
select tests.as_user('00000000-0000-0000-0000-00000000000a');   -- Ava: not a member
do $$ begin
  assert not exists (select 1 from public.clubs where name = 'Robotics Guild'), 'archived club hidden from non-members';
end $$;
reset role;
set role anon;
do $$ begin assert public.club_preview((select id from t_rg)) is null, 'archived club has no public shared-link page'; end $$;
reset role;
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-00000000000a');
select tests.fails($$select public.join_club((select id from t_rg), 'member', 'events', gen_random_uuid())$$, 'not_found|');
select tests.as_user('00000000-0000-0000-0000-0000000000a4');   -- Ivy: member keeps read access + history
do $$ begin
  assert exists (select 1 from public.clubs where name = 'Robotics Guild' and archived_at is not null);
  assert exists (select 1 from public.notifications where title = 'Robotics Guild is archived');
  assert exists (select 1 from public.attendance where user_id = auth.uid()), 'check-in history kept';
end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000e1');
select tests.fails($$select public.create_event(array[(select id from t_rg)], 'After archive', now() + interval '2 days', 60, '', '', gen_random_uuid())$$, 'validation|This club is archived');
select tests.fails($$select public.invite_officer((select id from t_rg), 'newbie@pride.hofstra.edu', 'Historian')$$, 'validation|This club is archived');
select public.archive_club((select id from t_rg), false);   -- unarchive
reset role;
do $$ begin assert (select archived_at is null from public.clubs where name = 'Robotics Guild'); end $$;
-- delete: a fresh club with no check-ins, president must type the name
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000e1');
create temp table t_del as select public.create_club('Delete Me Club', 'Games', 'x', '', 'DM', '#2c455d', false) as id;
grant select on t_del to authenticated;
select public.create_event(array[(select id from t_del)], 'Never happened', now() + interval '3 days', 60, '', '', gen_random_uuid());
select tests.fails($$select public.delete_club((select id from t_del), 'wrong name')$$, 'validation|Type the club');
select public.delete_club((select id from t_del), 'delete me club');
reset role;
do $$ begin
  assert not exists (select 1 from public.clubs where name = 'Delete Me Club');
  assert not exists (select 1 from public.events where title = 'Never happened'), 'its own events are deleted too';
end $$;
\echo 'ALL V8 TESTS PASSED'
