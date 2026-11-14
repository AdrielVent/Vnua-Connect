-- Tests for migration 20261115000000 (founding tools). Runs after v2_test.sql on the same database
-- (reuses its users and the Robotics Guild club: Eve = president, Finn = VP, Gia = treasurer, Ivy = member, Jo = muted member).
\set ON_ERROR_STOP 1
set client_min_messages = warning;

create temp table t_rg as select id from public.clubs where name = 'Robotics Guild';
grant select on t_rg to anon, authenticated;

-- ───────── Public previews: only published clubs, no private details ─────────
set role anon;
select tests.as_user(null);
do $$ declare j jsonb := public.club_preview((select id from t_rg)); begin
  assert j ->> 'name' = 'Robotics Guild';
  assert (j -> 'officers' -> 0 ->> 'name') = 'Eve', 'officers by first name only';
  assert j::text not like '%@%', 'no emails in a public preview';
end $$;
do $$ begin
  assert public.club_preview('10000000-0000-0000-0000-000000000003') is null, 'unpublished club has no public preview';
end $$;
select tests.fails('select * from public.polls', 'permission denied');
select tests.fails($$select public.vote_poll(gen_random_uuid(), 'yes')$$, 'permission denied');
reset role;

-- ───────── Membership preferences ─────────
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');   -- Ivy
select public.update_membership((select id from t_rg), 'all', 'organize', true);
do $$ begin
  assert (select involvement = 'organize' and recognition_ok and role = 'founding' from public.memberships
           where club_id = (select id from t_rg) and user_id = auth.uid());
end $$;
select tests.fails($$select public.update_membership((select id from t_rg), 'all', 'boss', true)$$, 'validation|');
select public.save_profile_extras(array['Design', 'Outreach'], array['Community']);

-- ───────── Events: newcomer info + edits ─────────
select tests.as_user('00000000-0000-0000-0000-0000000000e1');   -- Eve, president
create temp table t_ev3 as select public.create_event(array[(select id from t_rg)], 'Intro night',
  now() + interval '6 days', 60, '', '', gen_random_uuid(), '{1440}', '{"experience":"None needed","bring":"","evil":"<script>"}') as id;
grant select on t_ev3 to authenticated;
do $$ begin
  assert (select newcomer from public.events where id = (select id from t_ev3)) = '{"experience":"None needed"}'::jsonb, 'unknown/blank fields dropped';
end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');   -- members can't edit
select tests.fails($$select public.update_event((select id from t_ev3), 'X Y', now() + interval '6 days', 60, '', '', '{}', '{}')$$, 'forbidden|');
select tests.as_user('00000000-0000-0000-0000-0000000000f1');   -- VP moves it
select public.update_event((select id from t_ev3), 'Intro night', now() + interval '7 days', 90, 'Weed 120', '', '{1440,120}', '{"meet":"Outside the lab"}');
do $$ begin
  assert (select status = 'rescheduled' and previous_start is not null and location = 'Weed 120' from public.events where id = (select id from t_ev3));
end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
do $$ begin assert exists (select 1 from public.notifications where kind = 'event_changed'), 'members who want everything hear about the change'; end $$;

-- ───────── Feedback text stays hidden until 3 responses ─────────
select public.rate_event('20000000-0000-0000-0000-0000000000a2', 5, 'The demos', 'Start on time');
do $$ begin assert public.my_feedback('20000000-0000-0000-0000-0000000000a2') ->> 'keep' = 'The demos'; end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000e1');
do $$ declare s jsonb := public.event_stats('20000000-0000-0000-0000-0000000000a2'); begin
  assert s -> 'keep' = 'null'::jsonb and s -> 'change' = 'null'::jsonb, 'feedback text hidden below 3 responses';
end $$;

-- ───────── Insights include preferences ─────────
do $$ declare s jsonb := public.club_insights((select id from t_rg)); begin
  assert (select (m ->> 'recognition_ok')::boolean and m ->> 'involvement' = 'organize' and m -> 'help_with' ? 'Design'
            from jsonb_array_elements(s -> 'members') m where m ->> 'name' = 'Ivy M.');
end $$;

-- ───────── Tasks: officers only ─────────
create temp table t_task as select public.save_task(null, (select id from t_rg),
  'Book a room for intro night', '00000000-0000-0000-0000-0000000000f1', current_date + 3, (select id from t_ev3)) as id;
grant select on t_task to authenticated;
select tests.fails($$select public.save_task(null, (select id from t_rg), 'x y', '00000000-0000-0000-0000-0000000000a4', null, null)$$, 'validation|Pick an officer');
select tests.as_user('00000000-0000-0000-0000-0000000000f1');
do $$ begin assert exists (select 1 from public.notifications where kind = 'task'), 'owner told about the task'; end $$;
select public.set_task_done((select id from t_task), true);
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
do $$ begin assert (select count(*) from public.club_tasks) = 0, 'members cannot see tasks'; end $$;
select tests.fails($$select public.set_task_done((select id from t_task), false)$$, 'forbidden|');

-- ───────── Polls ─────────
select tests.as_user('00000000-0000-0000-0000-0000000000e1');
select tests.fails($$select public.create_poll((select id from t_rg), 'Kickoff', array[now() + interval '3 days'], 60, '', now() + interval '1 day')$$, 'validation|Offer 2');
select tests.fails($$select public.create_poll((select id from t_rg), 'Kickoff', array[now() + interval '3 days', now() + interval '4 days'], 60, '', now() + interval '5 days')$$, 'validation|Set the reply');
create temp table t_poll as select public.create_poll((select id from t_rg), 'Kickoff',
  array[now() + interval '3 days', now() + interval '4 days'], 60, 'Weed 120', now() + interval '2 days') as id;
grant select on t_poll to authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');   -- Ivy votes
do $$ begin assert exists (select 1 from public.notifications where kind = 'poll'); end $$;
select public.vote_poll((select id from public.poll_slots where poll_id = (select id from t_poll) order by starts_at limit 1), 'yes');
select tests.fails($$select public.vote_poll((select id from public.poll_slots where poll_id = (select id from t_poll) limit 1), 'sure')$$, 'validation|');
select tests.fails($$select public.poll_results((select id from t_poll))$$, 'forbidden|');
select tests.as_user('00000000-0000-0000-0000-00000000000a');   -- not a member
do $$ begin assert (select count(*) from public.polls) = 0, 'outsiders cannot see polls'; end $$;
select tests.fails($$select public.vote_poll((select id from public.poll_slots limit 1), 'yes')$$, 'not_found|');
select tests.as_user('00000000-0000-0000-0000-0000000000a2');   -- treasurer can't read individual votes
do $$ begin assert (select count(*) from public.poll_votes) = 0, 'votes are private'; end $$;
do $$ declare r jsonb := public.poll_results((select id from t_poll)); begin
  assert (r ->> 'responders')::int = 1 and (r -> 'slots' -> 0 ->> 'yes')::int = 1;
end $$;
create temp table t_sched as select public.schedule_poll((select id from t_poll),
  (select id from public.poll_slots where poll_id = (select id from t_poll) order by starts_at limit 1), gen_random_uuid()) as id;
do $$ begin
  assert (select title from public.events where id = (select id from t_sched)) = 'Kickoff';
  assert (select closed_at is not null from public.polls where id = (select id from t_poll)), 'poll closes once scheduled';
end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
do $$ begin assert exists (select 1 from public.notifications where kind = 'new_event' and title like 'It''s on: Kickoff%' or title = 'New: Kickoff'); end $$;
select tests.fails($$select public.vote_poll((select id from public.poll_slots where poll_id = (select id from t_poll) limit 1), 'no')$$, 'validation|This poll is closed');
reset role;

\echo 'ALL V3 TESTS PASSED'
