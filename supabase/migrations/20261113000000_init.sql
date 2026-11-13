-- Vnua-connect initial schema.
-- Security model:
--   * Clients may only SELECT through row-level security (RLS) policies.
--   * Every write goes through a SECURITY DEFINER function below, which checks the caller (auth.uid())
--     and enforces the same rules as VnuaConnect-iOS/VnuaConnect/API/MockAPI.swift.
--   * Errors are raised as 'code|Human message' so the app can map them to APIError.
--     codes: validation | forbidden | forbidden_role | last_admin | not_found | not_authenticated
--   * Writes that take a request_id are idempotent: a repeat returns the first successful result.

-- ───────────────────────────── Types ─────────────────────────────
create type public.member_role       as enum ('member', 'founding', 'officer');
create type public.membership_status as enum ('pending', 'active');
create type public.contact_pref      as enum ('none', 'events', 'organizing');
create type public.recognition       as enum ('recognized', 'not_recognized', 'not_stated');
create type public.event_status      as enum ('scheduled', 'rescheduled', 'cancelled');
create type public.checkin_mode      as enum ('pass', 'lookup', 'guest');
create type public.report_reason     as enum ('impersonation', 'duplicate', 'unsafe', 'wrong_status', 'other');

-- ───────────────────────────── Tables ─────────────────────────────
create table public.campuses (
  id            text primary key,
  name          text not null,
  email_domains text[] not null
);
insert into public.campuses (id, name, email_domains) values ('hofstra', 'Hofstra University', array['hofstra.edu']);

create table public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  campus_id         text not null references public.campuses (id),
  name              text not null check (char_length(btrim(name)) between 1 and 80),
  email             text not null,
  is_platform_admin boolean not null default false,
  created_at        timestamptz not null default now()
);

create table public.clubs (
  id                uuid primary key default gen_random_uuid(),
  campus_id         text not null references public.campuses (id),
  monogram          text not null check (char_length(monogram) between 1 and 3),
  accent_hex        text not null default '#1f5a6b' check (accent_hex ~ '^#[0-9a-fA-F]{6}$'),
  name              text not null check (char_length(btrim(name)) between 2 and 80),
  interest          text not null,
  blurb             text not null default '' check (char_length(blurb) <= 160),
  about             text not null default '' check (char_length(about) <= 2000),
  recognition       public.recognition not null default 'not_stated',
  funded            boolean,
  affiliation       text,
  requires_approval boolean not null default false,
  -- New clubs start unpublished; a platform admin publishes them (moderation queue).
  is_published      boolean not null default false,
  created_by        uuid references public.profiles (id) on delete set null,
  created_at        timestamptz not null default now(),
  unique (campus_id, name)
);

create table public.memberships (
  club_id       uuid not null references public.clubs (id) on delete cascade,
  user_id       uuid not null references public.profiles (id) on delete cascade,
  role          public.member_role not null default 'member',
  status        public.membership_status not null default 'active',
  contact       public.contact_pref not null default 'events',
  officer_title text,
  ask_about     text,
  created_at    timestamptz not null default now(),
  primary key (club_id, user_id)
);
create index on public.memberships (user_id);

create table public.events (
  id               uuid primary key default gen_random_uuid(),
  campus_id        text not null references public.campuses (id),
  title            text not null check (char_length(btrim(title)) between 2 and 140),
  starts_at        timestamptz not null,
  duration_minutes int not null default 60 check (duration_minutes between 5 and 1440),
  location         text not null default '',
  details          text not null default '',
  organizer        text not null default '',
  status           public.event_status not null default 'scheduled',
  previous_start   timestamptz,
  created_by       uuid references public.profiles (id) on delete set null,
  created_at       timestamptz not null default now()
);
create index on public.events (campus_id, starts_at);

-- One event can have several host clubs (joint events). Each person still counts once.
create table public.event_hosts (
  event_id uuid not null references public.events (id) on delete cascade,
  club_id  uuid not null references public.clubs (id) on delete cascade,
  primary key (event_id, club_id)
);
create index on public.event_hosts (club_id);

create table public.rsvps (
  event_id   uuid not null references public.events (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

-- Short-lived, event-bound pass tokens. Never readable by clients directly.
create table public.event_passes (
  token      text primary key,
  event_id   uuid not null references public.events (id) on delete cascade,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  expires_at timestamptz not null
);
create index on public.event_passes (expires_at);

create table public.attendance (
  id             uuid primary key default gen_random_uuid(),
  event_id       uuid not null references public.events (id) on delete cascade,
  user_id        uuid references public.profiles (id) on delete set null,
  attendee_name  text not null,
  mode           public.checkin_mode not null,
  recorded_at    timestamptz not null default now(),
  recorded_by    uuid references public.profiles (id) on delete set null,
  recorded_by_name text not null,
  -- Corrections never delete: the row stays, marked removed, with a reason.
  removed_reason text,
  removed_by     uuid references public.profiles (id) on delete set null,
  removed_at     timestamptz
);
-- Uniqueness: one live record per (event, person). Guests are matched by name.
create unique index attendance_one_live_member on public.attendance (event_id, user_id)
  where removed_at is null and user_id is not null;
create unique index attendance_one_live_guest on public.attendance (event_id, lower(attendee_name))
  where removed_at is null and user_id is null;

create table public.club_blocks (
  user_id    uuid not null references public.profiles (id) on delete cascade,
  club_id    uuid not null references public.clubs (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, club_id)
);

create table public.reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid references public.profiles (id) on delete set null,
  target_type text not null check (target_type in ('club', 'event')),
  target_id   uuid not null,
  reason      public.report_reason not null,
  detail      text not null default '' check (char_length(detail) <= 1000),
  status      text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  created_at  timestamptz not null default now()
);

-- Idempotency log for writes. Not readable by clients.
create table public.request_log (
  request_id uuid not null,
  user_id    uuid not null,
  result     jsonb not null,
  created_at timestamptz not null default now(),
  primary key (user_id, request_id)
);

-- ───────────────────────────── Helpers ─────────────────────────────
create function public.err(code text, msg text) returns void
language plpgsql as $$ begin raise exception '%|%', code, msg using errcode = 'P0001'; end $$;

create function public.require_user() returns uuid
language plpgsql stable as $$
declare me uuid := auth.uid();
begin
  if me is null then perform public.err('not_authenticated', 'Please sign in again.'); end if;
  return me;
end $$;

create function public.my_campus() returns text
language sql stable security definer set search_path = public as $$
  select campus_id from profiles where id = auth.uid()
$$;

create function public.is_club_member(p_club uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships where club_id = p_club and user_id = p_user and status = 'active')
$$;

create function public.is_club_officer(p_club uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships
                 where club_id = p_club and user_id = p_user and role = 'officer' and status = 'active')
$$;

create function public.is_event_officer(p_event uuid, p_user uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from event_hosts h join memberships m on m.club_id = h.club_id
                 where h.event_id = p_event and m.user_id = p_user and m.role = 'officer' and m.status = 'active')
$$;

create function public.is_platform_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_platform_admin from profiles where id = auth.uid()), false)
$$;

-- ───────────────────────────── Sign-up gate ─────────────────────────────
-- Runs when Supabase Auth creates a user. Rejects non-campus emails and creates the profile.
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  v_domain text := lower(split_part(new.email, '@', 2));
  v_campus text;
  v_name   text := btrim(coalesce(new.raw_user_meta_data ->> 'name', ''));
begin
  select id into v_campus from campuses c
   where exists (select 1 from unnest(c.email_domains) d where v_domain = d or v_domain like '%.' || d)
   limit 1;
  if v_campus is null then
    perform public.err('validation', 'Use your school email address.');
  end if;
  if v_name = '' then v_name := split_part(new.email, '@', 1); end if;
  insert into profiles (id, campus_id, name, email) values (new.id, v_campus, left(v_name, 80), lower(new.email));
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ───────────────────────────── Row-level security ─────────────────────────────
alter table public.campuses     enable row level security;
alter table public.profiles     enable row level security;
alter table public.clubs        enable row level security;
alter table public.memberships  enable row level security;
alter table public.events       enable row level security;
alter table public.event_hosts  enable row level security;
alter table public.rsvps        enable row level security;
alter table public.event_passes enable row level security;
alter table public.attendance   enable row level security;
alter table public.club_blocks  enable row level security;
alter table public.reports      enable row level security;
alter table public.request_log  enable row level security;

create policy campuses_read on public.campuses for select using (true);

-- Profiles: you see yourself. Other people's names reach officers only through the functions below.
create policy profiles_self on public.profiles for select using (id = auth.uid());

-- Clubs: published clubs on your campus, clubs you belong to, or everything if platform admin.
create policy clubs_read on public.clubs for select using (
  (is_published and campus_id = public.my_campus())
  or public.is_club_member(id, auth.uid())
  or exists (select 1 from public.memberships m where m.club_id = clubs.id and m.user_id = auth.uid())
  or public.is_platform_admin()
);

-- Memberships: your own rows; officers see their club's rows.
create policy memberships_read on public.memberships for select using (
  user_id = auth.uid() or public.is_club_officer(club_id, auth.uid())
);

-- Events: same campus, and at least one host club is visible to you.
-- (One SECURITY DEFINER helper for both tables avoids events ⇄ event_hosts policy recursion.)
create function public.can_see_event(p_event uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from events e join event_hosts h on h.event_id = e.id join clubs c on c.id = h.club_id
                  where e.id = p_event and e.campus_id = my_campus()
                    and (c.is_published or is_club_member(c.id, auth.uid())))
$$;
create policy events_read on public.events for select using (public.can_see_event(id));
create policy event_hosts_read on public.event_hosts for select using (public.can_see_event(event_id));

create policy rsvps_self on public.rsvps for select using (user_id = auth.uid());

-- Attendance: your own records (involvement), or all records of events you run.
create policy attendance_read on public.attendance for select using (
  user_id = auth.uid() or public.is_event_officer(event_id, auth.uid())
);

create policy blocks_self on public.club_blocks for select using (user_id = auth.uid());
create policy reports_self on public.reports for select using (reporter_id = auth.uid() or public.is_platform_admin());
-- event_passes, request_log: no policies → clients can never read them.

-- Public officer directory (names/titles only) for club pages.
create view public.club_officers with (security_barrier) as
  select m.club_id, p.name, coalesce(m.officer_title, 'Officer') as title, coalesce(m.ask_about, '') as ask_about
    from public.memberships m join public.profiles p on p.id = m.user_id
   where m.role = 'officer' and m.status = 'active';

-- ───────────────────────────── Write functions (RPC) ─────────────────────────────
create function public.idem_get(p_request uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select result from request_log where user_id = auth.uid() and request_id = p_request
$$;

create function public.idem_put(p_request uuid, p_result jsonb) returns jsonb
language sql security definer set search_path = public as $$
  insert into request_log (request_id, user_id, result) values (p_request, auth.uid(), p_result)
  on conflict do nothing;
  select p_result;
$$;

create function public.join_club(p_club uuid, p_role public.member_role, p_contact public.contact_pref, p_request uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); c clubs; m memberships; cached jsonb := idem_get(p_request);
begin
  if cached is not null then return cached; end if;
  if p_role not in ('member', 'founding') then perform err('forbidden_role', 'You can''t give yourself that role.'); end if;
  select * into c from clubs where id = p_club;
  if not found or c.campus_id <> my_campus() then perform err('not_found', 'That club no longer exists.'); end if;
  if exists (select 1 from club_blocks where user_id = me and club_id = p_club) then
    perform err('validation', 'Unblock this club before joining.');
  end if;
  insert into memberships (club_id, user_id, role, status, contact)
  values (p_club, me, p_role, (case when c.requires_approval then 'pending' else 'active' end)::membership_status, p_contact)
  on conflict (club_id, user_id) do update set contact = excluded.contact
  returning * into m;
  return idem_put(p_request, jsonb_build_object('club_id', m.club_id, 'role', m.role, 'status', m.status, 'contact', m.contact));
end $$;

create function public.update_contact(p_club uuid, p_contact public.contact_pref) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user();
begin
  update memberships set contact = p_contact where club_id = p_club and user_id = me;
  if not found then perform err('not_found', 'You''re not in this club.'); end if;
end $$;

create function public.leave_club(p_club uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user();
begin
  if is_club_officer(p_club, me) and not exists (
       select 1 from memberships where club_id = p_club and user_id <> me and role = 'officer' and status = 'active') then
    perform err('last_admin', 'You''re this club''s administrator. Transfer leadership before leaving.');
  end if;
  delete from memberships where club_id = p_club and user_id = me;
end $$;

create function public.join_requests(p_club uuid) returns table (user_id uuid, name text, role public.member_role, requested_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_club_officer(p_club, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  return query select m.user_id, p.name, m.role, m.created_at from memberships m join profiles p on p.id = m.user_id
                where m.club_id = p_club and m.status = 'pending' order by m.created_at;
end $$;

create function public.review_join_request(p_club uuid, p_user uuid, p_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_club_officer(p_club, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  if p_approve then
    update memberships set status = 'active' where club_id = p_club and user_id = p_user and status = 'pending';
  else
    delete from memberships where club_id = p_club and user_id = p_user and status = 'pending';
  end if;
  if not found then perform err('not_found', 'That request was already handled.'); end if;
end $$;

-- Found a new club: the creator becomes its officer. It stays unpublished until a platform admin approves it.
create function public.create_club(p_name text, p_interest text, p_blurb text, p_about text, p_monogram text,
                                   p_accent text, p_requires_approval boolean)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); v_id uuid;
begin
  insert into clubs (campus_id, monogram, accent_hex, name, interest, blurb, about, requires_approval, created_by)
  values (my_campus(), upper(p_monogram), p_accent, btrim(p_name), p_interest, p_blurb, p_about, p_requires_approval, me)
  returning id into v_id;
  insert into memberships (club_id, user_id, role, status, contact, officer_title)
  values (v_id, me, 'officer', 'active', 'organizing', 'Founder');
  return v_id;
exception when unique_violation then
  perform err('validation', 'A club with that name already exists.');
  return null;
end $$;

create function public.set_rsvp(p_event uuid, p_going boolean, p_request uuid) returns boolean
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); e events; cached jsonb := idem_get(p_request);
begin
  if cached is not null then return (cached ->> 'going')::boolean; end if;
  select * into e from events where id = p_event and campus_id = my_campus();
  if not found then perform err('not_found', 'That event no longer exists.'); end if;
  if p_going and e.status = 'cancelled' then perform err('validation', 'This event was cancelled.'); end if;
  if p_going then
    insert into rsvps (event_id, user_id) values (p_event, me) on conflict do nothing;
  else
    delete from rsvps where event_id = p_event and user_id = me;    -- never touches attendance
  end if;
  perform idem_put(p_request, jsonb_build_object('going', p_going));
  return p_going;
end $$;

create function public.issue_pass(p_event uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); v_token text; v_exp timestamptz := now() + interval '45 seconds';
begin
  if not exists (select 1 from events where id = p_event and campus_id = my_campus()) then
    perform err('not_found', 'That event no longer exists.');
  end if;
  delete from event_passes where expires_at < now() - interval '1 hour';    -- housekeeping
  v_token := 'VNUA-' || replace(gen_random_uuid()::text, '-', '');
  insert into event_passes (token, event_id, user_id, expires_at) values (v_token, p_event, me, v_exp);
  return jsonb_build_object('token', v_token, 'event_id', p_event, 'expires_at', v_exp);
end $$;

-- Officer search for the "Look up" check-in mode: members of host clubs and people who RSVP'd.
create function public.search_attendees(p_event uuid, p_query text) returns table (user_id uuid, name text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_event_officer(p_event, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  return query
    select distinct p.id, p.name from profiles p
     where (exists (select 1 from memberships m join event_hosts h on h.club_id = m.club_id
                     where h.event_id = p_event and m.user_id = p.id and m.status = 'active')
            or exists (select 1 from rsvps r where r.event_id = p_event and r.user_id = p.id))
       and p.name ilike '%' || replace(replace(btrim(p_query), '%', ''), '_', '') || '%'
     order by p.name limit 20;
end $$;

create function public.attendance_json(a attendance) returns jsonb
language sql stable as $$
  select jsonb_build_object('id', a.id, 'event_id', a.event_id, 'attendee_name', a.attendee_name, 'mode', a.mode,
                            'recorded_at', a.recorded_at, 'recorded_by_name', a.recorded_by_name,
                            'removed_reason', a.removed_reason)
$$;

create function public.check_in(p_event uuid, p_request uuid, p_token text default null,
                                p_member uuid default null, p_guest_name text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  me uuid := require_user();
  cached jsonb := idem_get(p_request);
  p event_passes; v_user uuid; v_name text; v_mode checkin_mode; rec attendance; v_status text := 'recorded';
begin
  if cached is not null then return cached; end if;
  if not is_event_officer(p_event, me) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  if num_nonnulls(p_token, p_member, p_guest_name) <> 1 then perform err('validation', 'Missing event or attendee.'); end if;

  if p_token is not null then
    select * into p from event_passes where token = p_token;
    if not found then perform err('validation', 'That code isn''t a Vnua-connect pass.'); end if;
    if p.event_id <> p_event then perform err('validation', 'This pass is for a different event.'); end if;
    if p.expires_at < now() then perform err('validation', 'This pass expired. Ask them to refresh it.'); end if;
    v_user := p.user_id; v_mode := 'pass';
  elsif p_member is not null then
    if not exists (select 1 from profiles where id = p_member and campus_id = my_campus()) then
      perform err('not_found', 'That person wasn''t found.');
    end if;
    v_user := p_member; v_mode := 'lookup';
  else
    v_name := btrim(p_guest_name);
    if v_name = '' then perform err('validation', 'Enter a name.'); end if;
    v_name := left(v_name, 80) || ' (guest)'; v_mode := 'guest';
  end if;
  if v_user is not null then select name into v_name from profiles where id = v_user; end if;

  insert into attendance (event_id, user_id, attendee_name, mode, recorded_by, recorded_by_name)
  values (p_event, v_user, v_name, v_mode, me, (select name from profiles where id = me))
  on conflict do nothing
  returning * into rec;

  if rec.id is null then
    v_status := 'duplicate';
    select * into rec from attendance
     where event_id = p_event and removed_at is null
       and ((v_user is not null and user_id = v_user)
         or (v_user is null and user_id is null and lower(attendee_name) = lower(v_name)));
  end if;
  return idem_put(p_request, jsonb_build_object('status', v_status, 'record', attendance_json(rec)));
end $$;

create function public.correct_attendance(p_record uuid, p_reason text, p_request uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); a attendance;
begin
  if idem_get(p_request) is not null then return; end if;
  if btrim(coalesce(p_reason, '')) = '' then perform err('validation', 'A reason is required.'); end if;
  select * into a from attendance where id = p_record;
  if not found then perform err('not_found', 'That record no longer exists.'); end if;
  if not is_event_officer(a.event_id, me) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  update attendance set removed_reason = btrim(p_reason), removed_by = me, removed_at = now()
   where id = p_record and removed_at is null;
  perform idem_put(p_request, '{}'::jsonb);
end $$;

create function public.block_club(p_club uuid, p_blocked boolean) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user();
begin
  if p_blocked then insert into club_blocks (user_id, club_id) values (me, p_club) on conflict do nothing;
  else delete from club_blocks where user_id = me and club_id = p_club; end if;
end $$;

create function public.report_content(p_type text, p_target uuid, p_reason public.report_reason, p_detail text) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user();
begin
  if (select count(*) from reports where reporter_id = me and created_at > now() - interval '1 hour') >= 20 then
    perform err('validation', 'Too many reports. Try again later.');
  end if;
  insert into reports (reporter_id, target_type, target_id, reason, detail) values (me, p_type, p_target, p_reason, coalesce(p_detail, ''));
end $$;

-- In-app account deletion (App Store guideline 5.1.1(v)). Anonymizes attendance so club history stays accurate.
create function public.delete_account() returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user();
begin
  update attendance set attendee_name = 'Deleted account' where user_id = me;
  delete from auth.users where id = me;
end $$;

-- ───────────────────────────── Grants ─────────────────────────────
-- Supabase grants table/function access to anon and authenticated by default. Tighten that:
-- signed-out users get nothing; signed-in users get SELECT (filtered by RLS) and the RPCs above.
revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from anon, public;
revoke insert, update, delete, truncate on all tables in schema public from authenticated;
grant select on all tables in schema public to authenticated;
-- Pass tokens and the idempotency log are server-only.
revoke all on public.event_passes, public.request_log from authenticated;
grant execute on function
  public.join_club, public.update_contact, public.leave_club, public.join_requests, public.review_join_request,
  public.create_club, public.set_rsvp, public.issue_pass, public.search_attendees, public.check_in,
  public.correct_attendance, public.block_club, public.report_content, public.delete_account,
  -- used inside RLS policies, so the caller needs execute:
  public.my_campus, public.is_club_member, public.is_club_officer, public.is_event_officer, public.is_platform_admin,
  public.can_see_event
to authenticated;
