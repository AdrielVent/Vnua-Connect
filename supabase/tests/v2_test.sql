-- Tests for profiles, officer teams, notifications, ratings and officer insights (migration 20261114000000).
-- Runs after security_test.sql on the same throwaway database (uses its tests.* helpers).
\set ON_ERROR_STOP 1
set client_min_messages = warning;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000e1', 'eve@pride.hofstra.edu',  '{"name":"Eve P."}'),   -- founder / president
  ('00000000-0000-0000-0000-0000000000f1', 'finn@pride.hofstra.edu', '{"name":"Finn V."}'),  -- vice president
  ('00000000-0000-0000-0000-0000000000a2', 'gia@pride.hofstra.edu',  '{"name":"Gia T."}'),   -- treasurer
  ('00000000-0000-0000-0000-0000000000a3', 'hal@pride.hofstra.edu',  '{"name":"Hal S."}'),   -- secretary
  ('00000000-0000-0000-0000-0000000000a4', 'ivy@pride.hofstra.edu',  '{"name":"Ivy M."}'),   -- member
  ('00000000-0000-0000-0000-0000000000a5', 'jo@pride.hofstra.edu',   '{"name":"Jo N."}');    -- outsider

set role authenticated;

-- ───────── Profiles / onboarding ─────────
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
select tests.fails($$select public.save_profile('Ivy', 'Bio', 'Junior', '', array['A','B','C','D'], '', '', '', false, false, true, true)$$, 'validation|Pick up to 3');
select tests.fails($$select public.save_profile('Ivy', 'Bio', 'Junior', '', array['Games'], '', '', 'https://evil.example/in/x', false, false, true, true)$$, 'validation|');
select public.save_profile('Ivy M.', 'Biology', 'Junior', 'she/her', array['Games', 'Engineering'], 'Hi!', '516 555 0100',
                           'linkedin.com/in/ivy', true, false, true, true);
do $$ begin
  assert (select onboarded_at is not null and linkedin = 'https://linkedin.com/in/ivy' from public.profiles where id = auth.uid());
end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000a5');
select public.save_profile('Jo N.', '', 'Senior', '', array['Games'], '', '', '', false, false, true, false);   -- not findable
do $$ begin assert (select count(*) from public.people_to_meet()) = 0, 'not findable → sees no one'; end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000f1');
select public.save_profile('Finn V.', 'CS', 'Sophomore', '', array['Games'], '', '516 555 0199', '', false, false, true, true);
do $$ begin
  assert (select count(*) from public.people_to_meet()) = 1, 'sees Ivy (shared interest, findable), not Jo';
  assert (select email from public.people_to_meet()) = 'ivy@pride.hofstra.edu', 'Ivy shares her email';
  assert (select phone from public.people_to_meet()) = '', 'Ivy did not share her phone';
end $$;

-- ───────── Officer team: a club needs all four core positions ─────────
select tests.as_user('00000000-0000-0000-0000-0000000000e1');
create temp table t_club as select public.create_club('Robotics Guild', 'Engineering', 'Build robots', '', 'RG', '#2c455d', false) as id;
grant select on t_club to authenticated;
do $$ begin
  assert (select officer_title from public.memberships where club_id = (select id from t_club) and user_id = auth.uid()) = 'President';
end $$;
reset role;
do $$ begin
  begin
    update public.clubs set is_published = true where id = (select id from t_club);
    raise exception 'published a club without a full officer team';
  exception when others then if sqlerrm not like 'validation|A club needs%' then raise; end if;
  end;
end $$;
set role authenticated;

select tests.as_user('00000000-0000-0000-0000-0000000000e1');
select tests.fails($$select public.invite_officer((select id from t_club), 'finn@gmail.com', 'Vice President')$$, 'validation|Use their school email');
select tests.fails($$select public.invite_officer((select id from t_club), 'eve@pride.hofstra.edu', 'Vice President')$$, 'validation|That''s you');
select tests.fails($$select public.invite_officer((select id from t_club), 'finn@pride.hofstra.edu', 'President')$$, 'validation|Someone already holds');
create temp table t_inv as select public.invite_officer((select id from t_club), 'finn@pride.hofstra.edu', 'Vice President') as id;
grant select on t_inv to authenticated;

select tests.as_user('00000000-0000-0000-0000-0000000000a5');   -- outsider
do $$ begin
  assert not exists (select 1 from public.clubs where id = (select id from t_club)), 'outsider cannot see a forming club';
  assert (select count(*) from public.club_invites) = 0, 'outsider cannot see invites';
end $$;
select tests.fails($$select public.respond_invite((select id from t_inv), true)$$, 'not_found|');
select tests.fails($$select public.invite_officer((select id from t_club), 'jo2@pride.hofstra.edu', 'Treasurer')$$, 'forbidden|');

select tests.as_user('00000000-0000-0000-0000-0000000000f1');   -- the invitee
do $$ begin
  assert exists (select 1 from public.clubs where id = (select id from t_club)), 'invitee can see the club';
  assert exists (select 1 from public.notifications where kind = 'invite'), 'invitee got an in-app invite';
end $$;
select public.respond_invite((select id from t_inv), true);
do $$ begin
  assert public.is_club_officer((select id from t_club), auth.uid());
  assert (select notify from public.memberships where club_id = (select id from t_club) and user_id = auth.uid()) = 'all';
end $$;

select tests.as_user('00000000-0000-0000-0000-0000000000e1');
create temp table t_inv2 as select public.invite_officer((select id from t_club), 'gia@pride.hofstra.edu', 'Treasurer') as id
  union all select public.invite_officer((select id from t_club), 'hal@pride.hofstra.edu', 'Secretary');
grant select on t_inv2 to authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000a2');
select public.respond_invite(i.id, true) from public.club_invites i where i.position = 'Treasurer' and i.status = 'pending';
select tests.as_user('00000000-0000-0000-0000-0000000000a3');
select public.respond_invite(i.id, true) from public.club_invites i where i.position = 'Secretary' and i.status = 'pending';
select tests.as_user('00000000-0000-0000-0000-0000000000e1');
do $$ begin
  assert (select count(*) from public.club_officers where club_id = (select id from t_club) and rank <= 4) = 4;
  assert exists (select 1 from public.notifications where kind = 'team_complete'), 'president told the team is complete';
  assert (select count(*) from public.club_officers where club_id = (select id from t_club)) = 4;
  assert (select phone from public.club_officers where name = 'Finn V.') = '', 'officer phone hidden unless shared';
  assert (select email from public.club_officers where name = 'Finn V.') = 'finn@pride.hofstra.edu';
end $$;
reset role;
update public.clubs set is_published = true where id = (select id from t_club);   -- moderator approves
set role authenticated;

-- Stepping down: the last officer can't leave the club officer-less.
select tests.as_user('00000000-0000-0000-0000-0000000000a3');
select public.update_officer_info((select id from t_club), 'Meeting notes and room bookings');
do $$ begin assert (select ask_about from public.club_officers where name = 'Hal S.') = 'Meeting notes and room bookings'; end $$;

-- ───────── Notifications: new events, reminders, mute ─────────
select tests.as_user('00000000-0000-0000-0000-0000000000a4');   -- Ivy joins, wants everything
select public.join_club((select id from t_club), 'member', 'events', gen_random_uuid(), 'all');
select tests.as_user('00000000-0000-0000-0000-0000000000a5');   -- Jo joins, mutes
select public.join_club((select id from t_club), 'member', 'events', gen_random_uuid(), 'none');

select tests.as_user('00000000-0000-0000-0000-0000000000e1');
select tests.fails($$select public.create_event(array[(select id from t_club)], 'Bad', now() + interval '1 day', 60, '', '', gen_random_uuid(), array[45])$$, 'validation|Pick reminder');
create temp table t_ev2 as select public.create_event(array[(select id from t_club)], 'Bot build night', now() + interval '3 days', 120, 'Weed Hall', '', gen_random_uuid(), array[1440, 120]) as id;
grant select on t_ev2 to authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
do $$ begin assert exists (select 1 from public.notifications where kind = 'new_event' and event_id = (select id from t_ev2)), 'Ivy (all) hears about new events'; end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000a5');
do $$ begin assert not exists (select 1 from public.notifications where kind = 'new_event'), 'Jo muted the club'; end $$;
select tests.fails($$select public.send_announcement((select id from t_club), 'Hi', 'x')$$, 'forbidden|');

-- A reminder is due: event starts in 2 hours, created yesterday, Jo RSVP'd but muted; Ivy didn't RSVP but chose "all".
reset role;
insert into public.events (id, campus_id, title, starts_at, duration_minutes, reminders, created_at) values
  ('20000000-0000-0000-0000-0000000000a1', 'hofstra', 'Soldering 101', now() + interval '115 minutes', 60, '{120}', now() - interval '1 day'),
  ('20000000-0000-0000-0000-0000000000a2', 'hofstra', 'Kickoff',       now() - interval '90 minutes',  60, '{120}', now() - interval '3 days');
insert into public.event_hosts values ('20000000-0000-0000-0000-0000000000a1', (select id from t_club)),
                                      ('20000000-0000-0000-0000-0000000000a2', (select id from t_club));
insert into public.rsvps values ('20000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a5', now());
do $$ declare n1 int; n2 int; begin
  n1 := public.send_due_notifications();
  n2 := public.send_due_notifications();
  assert n2 = 0, 'running the scheduler twice sends nothing new';
  assert exists (select 1 from public.notifications where user_id = '00000000-0000-0000-0000-0000000000a4' and kind = 'reminder'
                   and title like 'Soldering 101 starts in 2 hours'), 'Ivy gets the reminder';
  assert not exists (select 1 from public.notifications where user_id = '00000000-0000-0000-0000-0000000000a5' and kind = 'reminder'),
    'muted members get no reminders even if they RSVP''d';
end $$;
set role authenticated;

-- ───────── Ratings are anonymous ─────────
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
select tests.fails($$select public.rate_event('20000000-0000-0000-0000-0000000000a2', 5)$$, 'forbidden|Only people who checked in');
select tests.as_user('00000000-0000-0000-0000-0000000000f1');   -- VP checks Ivy in (all officers can run check-in)
select public.check_in('20000000-0000-0000-0000-0000000000a2', gen_random_uuid(), p_member => '00000000-0000-0000-0000-0000000000a4');
reset role;
do $$ begin assert public.send_due_notifications() >= 1; end $$;   -- rating prompt goes out 15+ min after the end
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
do $$ begin assert exists (select 1 from public.notifications where kind = 'rating' and event_id = '20000000-0000-0000-0000-0000000000a2'); end $$;
select tests.fails($$select public.rate_event('20000000-0000-0000-0000-0000000000a2', 9)$$, 'validation|');
select public.rate_event('20000000-0000-0000-0000-0000000000a2', 4);
do $$ begin assert public.my_rating('20000000-0000-0000-0000-0000000000a2') = 4; end $$;
select tests.fails('select * from public.event_ratings', 'permission denied');
select tests.fails($$select public.event_stats('20000000-0000-0000-0000-0000000000a2')$$, 'forbidden|');
select tests.fails($$select public.club_insights((select id from t_club))$$, 'forbidden|');
select tests.as_user('00000000-0000-0000-0000-0000000000a3');   -- secretary sees the stats
do $$ declare s jsonb := public.event_stats('20000000-0000-0000-0000-0000000000a2'); begin
  assert (s ->> 'checked_in')::int = 1 and (s ->> 'ratings')::int = 1;
  assert s -> 'rating_avg' = 'null'::jsonb, 'no average until 3 ratings (so one rating cannot be traced)';
end $$;

-- ───────── Insights, leaderboard, nudges ─────────
do $$ declare s jsonb := public.club_insights((select id from t_club)); begin
  assert jsonb_array_length(s -> 'members') = 6;
  assert (select (m ->> 'attended')::int from jsonb_array_elements(s -> 'members') m where m ->> 'name' = 'Ivy M.') = 1;
  assert (select (m ->> 'is_officer')::boolean from jsonb_array_elements(s -> 'members') m where m ->> 'name' = 'Eve P.');
end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
do $$ begin
  assert (select count(*) from public.club_leaderboard((select id from t_club))) = 1, 'officers are not on the leaderboard';
  assert (select is_me from public.club_leaderboard((select id from t_club)) limit 1);
end $$;
select tests.as_user('00000000-0000-0000-0000-00000000000a');   -- drama officer, not in Robotics
select tests.fails($$select * from public.club_leaderboard((select id from t_club))$$, 'forbidden|');
select tests.fails($$select public.nudge_members((select id from t_club), array['00000000-0000-0000-0000-0000000000a4'::uuid])$$, 'forbidden|');

select tests.as_user('00000000-0000-0000-0000-0000000000e1');
do $$ begin
  assert public.nudge_members((select id from t_club), array['00000000-0000-0000-0000-0000000000a4', '00000000-0000-0000-0000-0000000000f1']::uuid[]) = 1,
    'officers are never nudged';
  assert public.nudge_members((select id from t_club), array['00000000-0000-0000-0000-0000000000a4']::uuid[]) = 0, 'once a month at most';
end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
select public.respond_nudge((select id from public.notifications where kind = 'nudge'), 'busy');
do $$ begin assert (select paused_until > now() + interval '59 days' from public.memberships where club_id = (select id from t_club) and user_id = auth.uid()); end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000a5');
select tests.fails($$select public.respond_nudge((select id from public.notifications limit 1), 'leave')$$, 'not_found|');
select public.mark_notifications_read(null);

-- ───────── Officers ─────────
select tests.as_user('00000000-0000-0000-0000-0000000000e1');
select public.remove_officer((select id from t_club), '00000000-0000-0000-0000-0000000000a3');   -- Hal steps down
do $$ begin assert (select count(*) from public.club_officers where club_id = (select id from t_club) and rank <= 4) = 3; end $$;
select public.send_announcement((select id from t_club), 'Room change', 'We''re in Weed 120 this week.');
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
do $$ begin assert exists (select 1 from public.notifications where kind = 'announcement'); end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000a5');
do $$ begin assert not exists (select 1 from public.notifications where kind = 'announcement'), 'muted → no announcements'; end $$;
select tests.fails($$select public.set_club_logo((select id from t_club), 'https://evil.example/x.png')$$, 'forbidden|');
select tests.as_user('00000000-0000-0000-0000-0000000000e1');
select tests.fails($$select public.set_club_logo((select id from t_club), 'https://evil.example/x.png')$$, 'validation|');
reset role;
set role anon;
select tests.fails($$select public.people_to_meet()$$, 'permission denied');
select tests.fails($$select public.send_due_notifications()$$, 'permission denied');
reset role;
set role authenticated;
select tests.fails($$select public.send_due_notifications()$$, 'permission denied');
select tests.fails($$select public.notify_users(array[auth.uid()], 'announcement', null, null, 'spam', '', null)$$, 'permission denied');
select tests.fails($$select public.idem_put(gen_random_uuid(), '{}')$$, 'permission denied');
select tests.fails($$select public.club_core_filled(gen_random_uuid())$$, 'permission denied');
-- and the app's normal calls still work
select public.mark_notifications_read(null);
do $$ begin assert public.is_club_officer((select id from t_club), auth.uid()) is not null; end $$;
reset role;

\echo 'ALL V2 TESTS PASSED'
