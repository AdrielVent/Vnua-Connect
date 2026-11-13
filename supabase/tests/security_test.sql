-- Security tests for the Vnua-connect schema. Run with supabase/tests/run_local.sh.
-- Each test acts as a real signed-in user (role "authenticated" + a JWT "sub"), exactly like the app.
\set ON_ERROR_STOP 1
set client_min_messages = warning;

create schema tests;
grant usage on schema tests to authenticated, anon;

-- Act as a user (null = signed out).
create function tests.as_user(p uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', coalesce(json_build_object('sub', p)::text, ''), false);
end $$;

-- Run SQL and require it to fail with a message starting with `expect`.
create function tests.fails(p_sql text, expect text) returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if sqlerrm not like expect || '%' then
      raise exception 'expected error "%" but got "%" from: %', expect, sqlerrm, p_sql;
    end if;
    return;
  end;
  raise exception 'expected error "%" but it succeeded: %', expect, p_sql;
end $$;
grant execute on all functions in schema tests to authenticated, anon;

-- ───────── Fixtures (as superuser) ─────────
insert into public.campuses values ('otheru', 'Other University', array['other.edu']);

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'ava@pride.hofstra.edu', '{"name":"Ava R."}'),   -- officer of drama
  ('00000000-0000-0000-0000-00000000000b', 'ben@hofstra.edu',       '{"name":"Ben M."}'),   -- regular student
  ('00000000-0000-0000-0000-00000000000c', 'cy@pride.hofstra.edu',  '{"name":"Cy T."}'),    -- officer of pottery
  ('00000000-0000-0000-0000-00000000000d', 'dee@other.edu',         '{"name":"Dee O."}');   -- other campus

do $$ begin
  begin
    insert into auth.users (email) values ('mallory@gmail.com');
    raise exception 'non-campus email was allowed to sign up';
  exception when others then
    if sqlerrm not like 'validation|%' then raise; end if;
  end;
end $$;

insert into public.clubs (id, campus_id, monogram, name, interest, is_published, requires_approval) values
  ('10000000-0000-0000-0000-000000000001', 'hofstra', 'LD', 'Lowlight Drama Collective', 'Performing arts', true,  false),
  ('10000000-0000-0000-0000-000000000002', 'hofstra', 'HP', 'Harbor Street Pottery',     'Creative',        true,  true),
  ('10000000-0000-0000-0000-000000000003', 'hofstra', 'DR', 'Draft Club',                'Academic',        false, false),
  ('10000000-0000-0000-0000-000000000004', 'otheru',  'OT', 'Other Campus Club',         'Service',         true,  false);

insert into public.memberships (club_id, user_id, role) values
  ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', 'officer'),
  ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000c', 'officer');

insert into public.events (id, campus_id, title, starts_at, status) values
  ('20000000-0000-0000-0000-000000000001', 'hofstra', 'Read-through',       now() + interval '1 day', 'scheduled'),
  ('20000000-0000-0000-0000-000000000002', 'hofstra', 'Wheel basics',       now() + interval '2 day', 'scheduled'),
  ('20000000-0000-0000-0000-000000000003', 'hofstra', 'Joint workshop',     now() + interval '3 day', 'scheduled'),
  ('20000000-0000-0000-0000-000000000004', 'hofstra', 'Cancelled thing',    now() + interval '4 day', 'cancelled');
insert into public.event_hosts values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002'),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002'),
  ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000001');

-- ───────── 1. Signed-out users can read nothing ─────────
set role anon;
select tests.as_user(null);
select tests.fails('select * from public.clubs', 'permission denied');
select tests.fails($$select public.join_club('10000000-0000-0000-0000-000000000001', 'member', 'events', gen_random_uuid())$$, 'permission denied');
reset role;

-- ───────── 2. Directory visibility (campus isolation, unpublished clubs) ─────────
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  assert (select count(*) from public.clubs) = 2, 'Ben should see exactly the 2 published Hofstra clubs';
  assert not exists (select 1 from public.clubs where campus_id = 'otheru'), 'campus isolation broken';
  assert not exists (select 1 from public.clubs where name = 'Draft Club'), 'unpublished club leaked';
  assert (select count(*) from public.profiles) = 1, 'Ben should only see his own profile';
  assert (select count(*) from public.events) = 4, 'Ben should see the 4 Hofstra events';
end $$;
select tests.as_user('00000000-0000-0000-0000-00000000000d');
do $$ begin
  assert (select count(*) from public.clubs) = 1, 'Dee should only see her campus club';
  assert (select count(*) from public.events) = 0, 'Dee should see no Hofstra events';
end $$;

-- ───────── 3. No direct writes; no self-promotion ─────────
select tests.as_user('00000000-0000-0000-0000-00000000000b');
select tests.fails($$insert into public.memberships (club_id, user_id, role) values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000b', 'officer')$$, 'permission denied');
select tests.fails($$update public.profiles set is_platform_admin = true$$, 'permission denied');
select tests.fails($$insert into public.attendance (event_id, attendee_name, mode, recorded_by_name) values ('20000000-0000-0000-0000-000000000001', 'x', 'guest', 'x')$$, 'permission denied');
select tests.fails($$select public.join_club('10000000-0000-0000-0000-000000000001', 'officer', 'events', gen_random_uuid())$$, 'forbidden_role|');
select tests.fails('select * from public.request_log', 'permission denied');
select tests.fails('select * from public.event_passes', 'permission denied');

-- ───────── 4. Joining, approval queue ─────────
select public.join_club('10000000-0000-0000-0000-000000000001', 'member', 'events', '30000000-0000-0000-0000-000000000001');
-- same request id again returns the cached result, no error
select public.join_club('10000000-0000-0000-0000-000000000001', 'member', 'events', '30000000-0000-0000-0000-000000000001');
do $$ begin
  assert (select status from public.memberships where club_id = '10000000-0000-0000-0000-000000000001' and user_id = auth.uid()) = 'active';
end $$;
select public.join_club('10000000-0000-0000-0000-000000000002', 'founding', 'none', gen_random_uuid());
do $$ begin
  assert (select status from public.memberships where club_id = '10000000-0000-0000-0000-000000000002' and user_id = auth.uid()) = 'pending',
    'approval club should create a pending request';
end $$;
select tests.fails($$select * from public.join_requests('10000000-0000-0000-0000-000000000002')$$, 'forbidden|');
select tests.fails($$select public.review_join_request('10000000-0000-0000-0000-000000000002', auth.uid(), true)$$, 'forbidden|');
select tests.fails($$select public.join_club('10000000-0000-0000-0000-000000000004', 'member', 'events', gen_random_uuid())$$, 'not_found|');

select tests.as_user('00000000-0000-0000-0000-00000000000c');   -- pottery officer
do $$ begin
  assert (select count(*) from public.join_requests('10000000-0000-0000-0000-000000000002')) = 1;
  assert (select name from public.join_requests('10000000-0000-0000-0000-000000000002')) = 'Ben M.';
end $$;
select public.review_join_request('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000b', true);
do $$ begin
  assert (select status from public.memberships where club_id = '10000000-0000-0000-0000-000000000002'
          and user_id = '00000000-0000-0000-0000-00000000000b') = 'active', 'approval failed';
end $$;

-- ───────── 5. Check-in: officers only, and only for their own events ─────────
select tests.as_user('00000000-0000-0000-0000-00000000000b');   -- member, not officer
select tests.fails($$select public.check_in('20000000-0000-0000-0000-000000000001', gen_random_uuid(), p_guest_name => 'x')$$, 'forbidden|');
select tests.fails($$select * from public.search_attendees('20000000-0000-0000-0000-000000000001', 'a')$$, 'forbidden|');

select tests.as_user('00000000-0000-0000-0000-00000000000c');   -- pottery officer → drama event
select tests.fails($$select public.check_in('20000000-0000-0000-0000-000000000001', gen_random_uuid(), p_guest_name => 'x')$$, 'forbidden|');

-- Pass flow: Ben makes a pass for the drama event; Ava (drama officer) scans it.
select tests.as_user('00000000-0000-0000-0000-00000000000b');
create temp table t_pass as select public.issue_pass('20000000-0000-0000-0000-000000000001') ->> 'token' as token;
create temp table t_wrong as select public.issue_pass('20000000-0000-0000-0000-000000000002') ->> 'token' as token;
grant select on t_pass, t_wrong to authenticated;

select tests.as_user('00000000-0000-0000-0000-00000000000a');
do $$
declare r jsonb; r2 jsonb; r3 jsonb; tok text := (select token from t_pass);
begin
  r := public.check_in('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', p_token => tok);
  assert r ->> 'status' = 'recorded', 'first scan should record';
  assert r -> 'record' ->> 'attendee_name' = 'Ben M.';
  -- Retry with the same request id: identical result
  r2 := public.check_in('20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', p_token => tok);
  assert r2 = r, 'idempotent retry should return the same result';
  -- Same person via lookup, new request id: duplicate, not a second row
  r3 := public.check_in('20000000-0000-0000-0000-000000000001', gen_random_uuid(), p_member => '00000000-0000-0000-0000-00000000000b');
  assert r3 ->> 'status' = 'duplicate', 'second check-in of the same person should be a duplicate';
  assert (select count(*) from public.attendance where event_id = '20000000-0000-0000-0000-000000000001') = 1;
end $$;
select tests.fails(format($$select public.check_in('20000000-0000-0000-0000-000000000001', gen_random_uuid(), p_token => %L)$$,
                          (select token from t_wrong)), 'validation|This pass is for a different event');
select tests.fails($$select public.check_in('20000000-0000-0000-0000-000000000001', gen_random_uuid(), p_token => 'VNUA-fake')$$, 'validation|');
select tests.fails($$select public.check_in('20000000-0000-0000-0000-000000000001', gen_random_uuid())$$, 'validation|');

-- Expired pass
reset role;
update public.event_passes set expires_at = now() - interval '1 second' where token = (select token from t_pass);
delete from public.attendance;
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-00000000000a');
select tests.fails(format($$select public.check_in('20000000-0000-0000-0000-000000000001', gen_random_uuid(), p_token => %L)$$,
                          (select token from t_pass)), 'validation|This pass expired');

-- Guests: case-insensitive duplicate
do $$ begin
  assert public.check_in('20000000-0000-0000-0000-000000000001', gen_random_uuid(), p_guest_name => 'Leo') ->> 'status' = 'recorded';
  assert public.check_in('20000000-0000-0000-0000-000000000001', gen_random_uuid(), p_guest_name => 'leo') ->> 'status' = 'duplicate';
end $$;

-- Officer lookup search finds members/RSVPs of the event's host clubs only
do $$ begin
  assert exists (select 1 from public.search_attendees('20000000-0000-0000-0000-000000000001', 'ben')), 'Ben should be found';
  assert not exists (select 1 from public.search_attendees('20000000-0000-0000-0000-000000000001', 'dee')), 'other campus leaked';
end $$;

-- ───────── 6. Joint events: either host's officer can check in; person counts once ─────────
select tests.as_user('00000000-0000-0000-0000-00000000000c');
do $$ begin
  assert public.check_in('20000000-0000-0000-0000-000000000003', gen_random_uuid(), p_member => '00000000-0000-0000-0000-00000000000b') ->> 'status' = 'recorded';
end $$;
select tests.as_user('00000000-0000-0000-0000-00000000000a');
do $$ begin
  assert public.check_in('20000000-0000-0000-0000-000000000003', gen_random_uuid(), p_member => '00000000-0000-0000-0000-00000000000b') ->> 'status' = 'duplicate';
end $$;

-- ───────── 7. Attendance privacy + corrections ─────────
select tests.as_user('00000000-0000-0000-0000-00000000000b');
do $$ begin
  assert (select count(*) from public.attendance) = 1, 'Ben should only see his own attendance (joint workshop)';
end $$;
select tests.fails($$select public.correct_attendance((select id from public.attendance limit 1), 'x', gen_random_uuid())$$, 'forbidden|');

select tests.as_user('00000000-0000-0000-0000-00000000000a');
select tests.fails($$select public.correct_attendance((select id from public.attendance where attendee_name = 'Leo (guest)'), '   ', gen_random_uuid())$$, 'validation|A reason is required');
select public.correct_attendance((select id from public.attendance where attendee_name = 'Leo (guest)'), 'Wrong person', gen_random_uuid());
do $$ begin
  assert (select removed_reason from public.attendance where attendee_name = 'Leo (guest)') = 'Wrong person', 'original row must be kept';
  -- After a correction the guest can be checked in again
  assert public.check_in('20000000-0000-0000-0000-000000000001', gen_random_uuid(), p_guest_name => 'Leo') ->> 'status' = 'recorded';
end $$;

-- ───────── 8. Leaving: the last officer can't leave ─────────
select tests.fails($$select public.leave_club('10000000-0000-0000-0000-000000000001')$$, 'last_admin|');
reset role;
insert into public.memberships (club_id, user_id, role) values ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000c', 'officer');
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-00000000000a');
select public.leave_club('10000000-0000-0000-0000-000000000001');   -- now allowed

-- ───────── 9. RSVPs ─────────
select tests.as_user('00000000-0000-0000-0000-00000000000b');
select tests.fails($$select public.set_rsvp('20000000-0000-0000-0000-000000000004', true, gen_random_uuid())$$, 'validation|This event was cancelled');
select public.set_rsvp('20000000-0000-0000-0000-000000000002', true, gen_random_uuid());
select tests.as_user('00000000-0000-0000-0000-00000000000c');
do $$ begin assert (select count(*) from public.rsvps) = 0, 'RSVPs are private'; end $$;

-- ───────── 10. Block, report, found a club ─────────
select tests.as_user('00000000-0000-0000-0000-00000000000b');
select public.block_club('10000000-0000-0000-0000-000000000002', true);
select public.leave_club('10000000-0000-0000-0000-000000000002');
select tests.fails($$select public.join_club('10000000-0000-0000-0000-000000000002', 'member', 'events', gen_random_uuid())$$, 'validation|Unblock');
select public.report_content('club', '10000000-0000-0000-0000-000000000001', 'impersonation', 'test');
create temp table t_new as select public.create_club('Chess Night', 'Games', 'Casual chess', '', 'CN', '#2c455d', false) as id;
do $$ begin
  assert (select role from public.memberships where club_id = (select id from t_new) and user_id = auth.uid()) = 'officer';
end $$;
select tests.as_user('00000000-0000-0000-0000-00000000000c');
do $$ begin assert not exists (select 1 from public.clubs where name = 'Chess Night'), 'new club must wait for moderation'; end $$;

-- ───────── 11. Account deletion ─────────
select tests.as_user('00000000-0000-0000-0000-00000000000b');
select public.delete_account();
reset role;
do $$ begin
  assert not exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-00000000000b');
  assert not exists (select 1 from public.attendance where attendee_name = 'Ben M.'), 'attendance must be anonymized';
  assert exists (select 1 from public.attendance where attendee_name = 'Deleted account'), 'club history must be kept';
end $$;

\echo 'ALL SECURITY TESTS PASSED'
