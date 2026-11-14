-- v2: student profiles + onboarding, officer teams (president/VP/treasurer/secretary), club logos,
-- in-app notifications with scheduled event reminders, anonymous ratings, officer insights,
-- "still interested?" nudges, member leaderboard and "people to meet".
-- Same security model as init: reads through RLS, every write through a SECURITY DEFINER function.

-- ───────────────────────────── Columns ─────────────────────────────
alter table public.campuses add column timezone text not null default 'America/New_York';

alter table public.profiles
  add column major          text not null default '' check (char_length(major) <= 80),
  add column class_year     text not null default '' check (class_year in ('', 'Freshman', 'Sophomore', 'Junior', 'Senior', 'Grad student', 'Alum', 'Faculty/Staff')),
  add column pronouns       text not null default '' check (char_length(pronouns) <= 30),
  add column bio            text not null default '' check (char_length(bio) <= 280),
  add column interests      text[] not null default '{}' check (cardinality(interests) <= 3),
  add column phone          text not null default '' check (phone ~ '^[0-9 +().-]{0,30}$'),
  add column linkedin       text not null default '' check (linkedin = '' or linkedin ~* '^https://([a-z]+\.)?linkedin\.com/'),
  add column share_email    boolean not null default false,
  add column share_phone    boolean not null default false,
  add column share_linkedin boolean not null default true,
  add column discoverable   boolean not null default false,   -- appears in "People to meet"
  add column leaderboard    boolean not null default true,    -- appears on club leaderboards
  add column onboarded_at   timestamptz;

alter table public.clubs add column logo_url text check (logo_url is null or char_length(logo_url) <= 500);

-- notify: 'all' = new events, announcements and reminders for every event
--         'rsvp' = announcements + reminders for events you RSVP to (default)
--         'none' = nothing; you check the app yourself
alter table public.memberships
  add column notify       text not null default 'rsvp' check (notify in ('all', 'rsvp', 'none')),
  add column paused_until timestamptz;                         -- "busy, but still in": no nudges until then

-- Minutes before the start. Officers pick any of these per event.
alter table public.events
  add column reminders int[] not null default '{1440,120}'
  check (reminders <@ array[20160, 10080, 4320, 1440, 120, 60, 30] and cardinality(reminders) <= 7);

alter table public.reports drop constraint reports_target_type_check;
alter table public.reports add constraint reports_target_type_check check (target_type in ('club', 'event', 'profile'));

-- One person per officer title in a club (so there is exactly one President, etc.).
update public.memberships set officer_title = 'President'
 where role = 'officer' and officer_title = 'Founder'
   and not exists (select 1 from public.memberships x where x.club_id = memberships.club_id and lower(x.officer_title) = 'president');
create unique index memberships_one_title on public.memberships (club_id, lower(officer_title))
  where role = 'officer' and officer_title is not null;

-- ───────────────────────────── New tables ─────────────────────────────
create table public.club_invites (
  id           uuid primary key default gen_random_uuid(),
  club_id      uuid not null references public.clubs (id) on delete cascade,
  email        text not null,
  position     text not null check (char_length(btrim(position)) between 2 and 40),
  invited_by   uuid references public.profiles (id) on delete set null,
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'revoked')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz
);
create unique index club_invites_one_per_position on public.club_invites (club_id, lower(position)) where status = 'pending';
create unique index club_invites_one_per_email on public.club_invites (club_id, email) where status = 'pending';
create index on public.club_invites (email) where status = 'pending';

create table public.notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  kind       text not null check (kind in ('reminder', 'new_event', 'cancelled', 'rating', 'nudge', 'invite', 'approved', 'team_complete', 'announcement')),
  club_id    uuid references public.clubs (id) on delete cascade,
  event_id   uuid references public.events (id) on delete cascade,
  title      text not null,
  body       text not null default '',
  dedupe     text,
  created_at timestamptz not null default now(),
  read_at    timestamptz,
  acted_at   timestamptz,
  unique (user_id, dedupe)
);
create index on public.notifications (user_id, created_at desc);
create index on public.notifications (club_id, kind, created_at desc);

-- Anonymous: no client can read this table. Officers only get averages from 3+ ratings.
create table public.event_ratings (
  id         uuid primary key default gen_random_uuid(),
  event_id   uuid not null references public.events (id) on delete cascade,
  user_id    uuid references public.profiles (id) on delete set null,
  stars      smallint not null check (stars between 1 and 5),
  created_at timestamptz not null default now(),
  unique (event_id, user_id)
);

-- ───────────────────────────── Helpers ─────────────────────────────
create function public.my_email() returns text
language sql stable security definer set search_path = public as $$
  select email from profiles where id = auth.uid()
$$;

create function public.position_rank(t text) returns int
language sql immutable as $$
  select case lower(coalesce(t, '')) when 'president' then 1 when 'vice president' then 2
              when 'treasurer' then 3 when 'secretary' then 4 else 5 end
$$;

-- How many of the four core positions are held by an active officer.
create function public.club_core_filled(p_club uuid) returns int
language sql stable security definer set search_path = public as $$
  select count(distinct lower(officer_title))::int from memberships
   where club_id = p_club and role = 'officer' and status = 'active'
     and lower(officer_title) in ('president', 'vice president', 'treasurer', 'secretary')
$$;

create function public.can_see_club(p_club uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from clubs c where c.id = p_club and (
           (c.is_published and c.campus_id = my_campus())
        or exists (select 1 from memberships m where m.club_id = c.id and m.user_id = auth.uid())
        or exists (select 1 from club_invites i where i.club_id = c.id and i.status = 'pending' and i.email = my_email())
        or is_platform_admin()))
$$;

drop policy clubs_read on public.clubs;
create policy clubs_read on public.clubs for select using (public.can_see_club(id));

-- A club can only be published once all four core positions are filled.
create function public.clubs_publish_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.is_published and not coalesce(old.is_published, false) and club_core_filled(new.id) < 4 then
    perform err('validation', 'A club needs a president, vice president, treasurer and secretary before it can be published.');
  end if;
  return new;
end $$;
create trigger clubs_publish_guard before update of is_published on public.clubs
  for each row execute function public.clubs_publish_guard();

-- Officer directory for club pages: officers agree to show their name, position and school email when they accept.
drop view public.club_officers;
create view public.club_officers with (security_barrier) as
  select m.club_id, m.user_id, p.name, coalesce(m.officer_title, 'Officer') as title, coalesce(m.ask_about, '') as ask_about,
         p.email, case when p.share_phone then p.phone else '' end as phone,
         case when p.share_linkedin then p.linkedin else '' end as linkedin,
         p.major, p.class_year, p.pronouns, public.position_rank(m.officer_title) as rank
    from public.memberships m join public.profiles p on p.id = m.user_id
   where m.role = 'officer' and m.status = 'active' and public.can_see_club(m.club_id);

alter table public.club_invites  enable row level security;
alter table public.notifications enable row level security;
alter table public.event_ratings enable row level security;
create policy invites_read on public.club_invites for select using (
  email = public.my_email() or public.is_club_officer(club_id, auth.uid())
);
create policy notifications_self on public.notifications for select using (user_id = auth.uid());
-- event_ratings: no policy → never readable by clients.

-- Insert one notification per user; repeats with the same dedupe key are ignored.
create function public.notify_users(p_users uuid[], p_kind text, p_club uuid, p_event uuid,
                                    p_title text, p_body text, p_dedupe text) returns int
language sql security definer set search_path = public as $$
  with ins as (
    insert into notifications (user_id, kind, club_id, event_id, title, body, dedupe)
    select distinct u, p_kind, p_club, p_event, left(p_title, 140), left(coalesce(p_body, ''), 500), p_dedupe
      from unnest(p_users) u where u is not null
    on conflict (user_id, dedupe) do nothing returning 1)
  select count(*)::int from ins
$$;

-- Who hears about an event: people who RSVP'd (unless they muted a host club) plus members who chose "everything".
-- Anyone who blocked a host club is left out.
create function public.event_audience(p_event uuid) returns setof uuid
language sql stable security definer set search_path = public as $$
  (select r.user_id from rsvps r where r.event_id = p_event
      and not exists (select 1 from memberships m join event_hosts h on h.club_id = m.club_id
                       where h.event_id = p_event and m.user_id = r.user_id and m.notify = 'none')
   union
   select m.user_id from memberships m join event_hosts h on h.club_id = m.club_id
    where h.event_id = p_event and m.status = 'active' and m.notify = 'all')
  except
  select b.user_id from club_blocks b join event_hosts h on h.club_id = b.club_id where h.event_id = p_event
$$;

create function public.reminder_label(m int) returns text
language sql immutable as $$
  select case m when 20160 then 'in 2 weeks' when 10080 then 'in 1 week' when 4320 then 'in 3 days'
                when 1440 then 'in 24 hours' when 120 then 'in 2 hours' when 60 then 'in 1 hour'
                when 30 then 'in 30 minutes' else 'soon' end
$$;

create function public.event_when(p_event uuid) returns text
language sql stable security definer set search_path = public as $$
  select to_char(e.starts_at at time zone c.timezone, 'FMDy, FMMon FMDD at FMHH12:MI AM')
         || case when e.location <> '' then ' · ' || e.location else '' end
    from events e join campuses c on c.id = e.campus_id where e.id = p_event
$$;

-- ───────────────────────────── Profile + onboarding ─────────────────────────────
create function public.save_profile(p_name text, p_major text, p_year text, p_pronouns text, p_interests text[], p_bio text,
                                    p_phone text, p_linkedin text, p_share_email boolean, p_share_phone boolean,
                                    p_share_linkedin boolean, p_discoverable boolean, p_leaderboard boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); v_li text := btrim(coalesce(p_linkedin, ''));
begin
  if char_length(btrim(coalesce(p_name, ''))) < 1 then perform err('validation', 'Enter your name.'); end if;
  if cardinality(coalesce(p_interests, '{}')) > 3 then perform err('validation', 'Pick up to 3 interests.'); end if;
  if v_li <> '' and v_li !~* '^https?://' then v_li := 'https://' || v_li; end if;
  if v_li ~* '^http://' then v_li := 'https://' || substr(v_li, 8); end if;
  if v_li <> '' and v_li !~* '^https://([a-z]+\.)?linkedin\.com/' then
    perform err('validation', 'That doesn''t look like a LinkedIn link (linkedin.com/in/…).');
  end if;
  if btrim(coalesce(p_phone, '')) !~ '^[0-9 +().-]{0,30}$' then perform err('validation', 'Use digits only for your phone number.'); end if;
  update profiles set name = left(btrim(p_name), 80), major = left(btrim(coalesce(p_major, '')), 80),
         class_year = coalesce(p_year, ''), pronouns = left(btrim(coalesce(p_pronouns, '')), 30),
         interests = array(select distinct left(btrim(x), 40) from unnest(coalesce(p_interests, '{}')) x where btrim(x) <> ''),
         bio = left(btrim(coalesce(p_bio, '')), 280), phone = btrim(coalesce(p_phone, '')), linkedin = v_li,
         share_email = coalesce(p_share_email, false), share_phone = coalesce(p_share_phone, false),
         share_linkedin = coalesce(p_share_linkedin, true), discoverable = coalesce(p_discoverable, false),
         leaderboard = coalesce(p_leaderboard, true), onboarded_at = coalesce(onboarded_at, now())
   where id = me;
exception when check_violation then
  perform err('validation', 'Check your profile details.');
end $$;

-- ───────────────────────────── Clubs ─────────────────────────────
drop function public.create_club(text, text, text, text, text, text, boolean);
create function public.create_club(p_name text, p_interest text, p_blurb text, p_about text, p_monogram text,
                                   p_accent text, p_requires_approval boolean, p_position text default 'President')
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); v_id uuid; v_pos text := coalesce(nullif(btrim(p_position), ''), 'President');
begin
  if (select count(*) from clubs where created_by = me and created_at > now() - interval '1 day') >= 5 then
    perform err('validation', 'You''ve started a lot of clubs today. Try again tomorrow.');
  end if;
  insert into clubs (campus_id, monogram, accent_hex, name, interest, blurb, about, requires_approval, created_by)
  values (my_campus(), upper(p_monogram), p_accent, btrim(p_name), p_interest, p_blurb, p_about, p_requires_approval, me)
  returning id into v_id;
  insert into memberships (club_id, user_id, role, status, contact, officer_title, notify)
  values (v_id, me, 'officer', 'active', 'organizing', left(v_pos, 40), 'all');
  return v_id;
exception when unique_violation then
  perform err('validation', 'A club with that name already exists.');
  return null;
end $$;

create function public.update_club(p_club uuid, p_name text, p_interest text, p_blurb text, p_about text, p_monogram text,
                                   p_accent text, p_requires_approval boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_club_officer(p_club, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  update clubs set name = btrim(p_name), interest = p_interest, blurb = coalesce(p_blurb, ''), about = coalesce(p_about, ''),
         monogram = upper(p_monogram), accent_hex = p_accent, requires_approval = coalesce(p_requires_approval, false)
   where id = p_club;
exception
  when unique_violation then perform err('validation', 'A club with that name already exists.');
  when check_violation then perform err('validation', 'Check the club details (name 2–80 characters, one-liner up to 160).');
end $$;

-- Logo files live in the public "club-logos" storage bucket under <club id>/.
create function public.set_club_logo(p_club uuid, p_url text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_club_officer(p_club, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  if p_url is not null and p_url not like '%/storage/v1/object/public/club-logos/' || p_club::text || '/%' then
    perform err('validation', 'Upload the logo through the app.');
  end if;
  update clubs set logo_url = p_url where id = p_club;
end $$;

-- ───────────────────────────── Officer team ─────────────────────────────
create function public.invite_officer(p_club uuid, p_email text, p_position text) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  me uuid := require_user();
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_pos text := btrim(coalesce(p_position, ''));
  v_domain text := split_part(lower(btrim(coalesce(p_email, ''))), '@', 2);
  v_id uuid;
begin
  if not is_club_officer(p_club, me) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  if char_length(v_pos) not between 2 and 40 then perform err('validation', 'Name the position (2–40 characters).'); end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' or not exists (
       select 1 from campuses c where c.id = my_campus()
          and exists (select 1 from unnest(c.email_domains) d where v_domain = d or v_domain like '%.' || d)) then
    perform err('validation', 'Use their school email address.');
  end if;
  if v_email = my_email() then perform err('validation', 'That''s you. Invite someone else.'); end if;
  if exists (select 1 from memberships m join profiles p on p.id = m.user_id
              where m.club_id = p_club and p.email = v_email and m.role = 'officer' and m.status = 'active') then
    perform err('validation', 'They''re already an officer.');
  end if;
  if exists (select 1 from memberships where club_id = p_club and role = 'officer' and status = 'active'
                                         and lower(officer_title) = lower(v_pos)) then
    perform err('validation', 'Someone already holds that position.');
  end if;
  if (select count(*) from club_invites where club_id = p_club and created_at > now() - interval '1 day') >= 30 then
    perform err('validation', 'Too many invites today. Try again tomorrow.');
  end if;
  -- A new invite for the same position or person replaces the old one.
  update club_invites set status = 'revoked', responded_at = now()
   where club_id = p_club and status = 'pending' and (lower(position) = lower(v_pos) or email = v_email);
  insert into club_invites (club_id, email, position, invited_by) values (p_club, v_email, v_pos, me) returning id into v_id;
  perform notify_users(array(select id from profiles where email = v_email), 'invite', p_club, null,
    'You''re invited to be ' || v_pos, (select name from clubs where id = p_club) || ' wants you on its officer team.', 'inv:' || v_id);
  return v_id;
end $$;

create function public.revoke_invite(p_invite uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_club uuid := (select club_id from club_invites where id = p_invite);
begin
  if v_club is null or not is_club_officer(v_club, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  update club_invites set status = 'revoked', responded_at = now() where id = p_invite and status = 'pending';
end $$;

create function public.respond_invite(p_invite uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); i club_invites;
begin
  select * into i from club_invites where id = p_invite and status = 'pending';
  if not found or i.email <> my_email() then perform err('not_found', 'That invite is no longer open.'); end if;
  update notifications set acted_at = now(), read_at = coalesce(read_at, now()) where user_id = me and dedupe = 'inv:' || p_invite;
  if not p_accept then
    update club_invites set status = 'declined', responded_at = now() where id = p_invite;
    return;
  end if;
  if exists (select 1 from memberships where club_id = i.club_id and user_id <> me and role = 'officer'
                                         and status = 'active' and lower(officer_title) = lower(i.position)) then
    update club_invites set status = 'revoked', responded_at = now() where id = p_invite;
    perform err('validation', 'Someone else already took that position.');
  end if;
  insert into memberships (club_id, user_id, role, status, contact, officer_title, notify)
  values (i.club_id, me, 'officer', 'active', 'organizing', i.position, 'all')
  on conflict (club_id, user_id) do update set role = 'officer', status = 'active', officer_title = excluded.officer_title,
                                               contact = 'organizing', notify = 'all';
  update club_invites set status = 'accepted', responded_at = now() where id = p_invite;
  if club_core_filled(i.club_id) = 4 then
    perform notify_users(array(select user_id from memberships where club_id = i.club_id and role = 'officer' and status = 'active'),
      'team_complete', i.club_id, null, 'Your officer team is complete',
      'President, vice president, treasurer and secretary are all set. A moderator will review the club next.',
      'complete:' || i.club_id);
  end if;
end $$;

-- Your "contact me about…" line on the club page.
create function public.update_officer_info(p_club uuid, p_ask_about text) returns void
language plpgsql security definer set search_path = public as $$
begin
  update memberships set ask_about = left(btrim(coalesce(p_ask_about, '')), 140)
   where club_id = p_club and user_id = require_user() and role = 'officer';
  if not found then perform err('not_found', 'You''re not an officer of this club.'); end if;
end $$;

-- Step down (yourself) or remove another officer. They stay a member.
create function public.remove_officer(p_club uuid, p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user();
begin
  if not is_club_officer(p_club, me) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  if not exists (select 1 from memberships where club_id = p_club and user_id <> p_user and role = 'officer' and status = 'active') then
    perform err('last_admin', 'A club needs at least one officer. Invite someone else first.');
  end if;
  update memberships set role = 'member', officer_title = null, ask_about = null
   where club_id = p_club and user_id = p_user and role = 'officer';
  if not found then perform err('not_found', 'They''re not an officer.'); end if;
end $$;

-- ───────────────────────────── Membership ─────────────────────────────
drop function public.join_club(uuid, public.member_role, public.contact_pref, uuid);
create function public.join_club(p_club uuid, p_role public.member_role, p_contact public.contact_pref, p_request uuid,
                                 p_notify text default 'rsvp')
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); c clubs; m memberships; cached jsonb := idem_get(p_request);
begin
  if cached is not null then return cached; end if;
  if p_role not in ('member', 'founding') then perform err('forbidden_role', 'You can''t give yourself that role.'); end if;
  if coalesce(p_notify, 'rsvp') not in ('all', 'rsvp', 'none') then perform err('validation', 'Pick a notification setting.'); end if;
  select * into c from clubs where id = p_club;
  if not found or c.campus_id <> my_campus() or not can_see_club(p_club) then perform err('not_found', 'That club no longer exists.'); end if;
  if exists (select 1 from club_blocks where user_id = me and club_id = p_club) then
    perform err('validation', 'Unblock this club before joining.');
  end if;
  insert into memberships (club_id, user_id, role, status, contact, notify)
  values (p_club, me, p_role, (case when c.requires_approval then 'pending' else 'active' end)::membership_status, p_contact,
          coalesce(p_notify, 'rsvp'))
  on conflict (club_id, user_id) do update set contact = excluded.contact, notify = excluded.notify
  returning * into m;
  return idem_put(p_request, jsonb_build_object('club_id', m.club_id, 'role', m.role, 'status', m.status,
                                                'contact', m.contact, 'notify', m.notify));
end $$;

create function public.update_notify(p_club uuid, p_notify text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_notify not in ('all', 'rsvp', 'none') then perform err('validation', 'Pick a notification setting.'); end if;
  update memberships set notify = p_notify where club_id = p_club and user_id = require_user();
  if not found then perform err('not_found', 'You''re not in this club.'); end if;
end $$;

create or replace function public.review_join_request(p_club uuid, p_user uuid, p_approve boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_club_officer(p_club, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  if p_approve then
    update memberships set status = 'active' where club_id = p_club and user_id = p_user and status = 'pending';
  else
    delete from memberships where club_id = p_club and user_id = p_user and status = 'pending';
  end if;
  if not found then perform err('not_found', 'That request was already handled.'); end if;
  if p_approve then
    perform notify_users(array[p_user], 'approved', p_club, null, 'You''re in',
      'Your request to join ' || (select name from clubs where id = p_club) || ' was approved.', 'approved:' || p_club);
  end if;
end $$;

-- ───────────────────────────── Events ─────────────────────────────
drop function public.create_event(uuid[], text, timestamptz, int, text, text, uuid);
create function public.create_event(p_hosts uuid[], p_title text, p_starts_at timestamptz, p_duration int,
                                    p_location text, p_details text, p_request uuid, p_reminders int[] default '{1440,120}')
returns uuid language plpgsql security definer set search_path = public as $$
declare
  me uuid := require_user();
  cached jsonb := idem_get(p_request);
  v_id uuid;
  v_host uuid;
begin
  if cached is not null then return (cached ->> 'id')::uuid; end if;
  if coalesce(array_length(p_hosts, 1), 0) = 0 then perform err('validation', 'Pick a host club.'); end if;
  foreach v_host in array p_hosts loop
    if not is_club_officer(v_host, me) then
      perform err('forbidden', 'You need to be an officer of every host club.');
    end if;
    if (select campus_id from clubs where id = v_host) <> my_campus() then
      perform err('not_found', 'That club no longer exists.');
    end if;
  end loop;
  if char_length(btrim(coalesce(p_title, ''))) < 2 then perform err('validation', 'Give the event a title.'); end if;
  if p_starts_at < now() - interval '1 hour' then perform err('validation', 'Pick a start time in the future.'); end if;
  if not coalesce(p_reminders, '{}') <@ array[20160, 10080, 4320, 1440, 120, 60, 30] then
    perform err('validation', 'Pick reminder times from the list.');
  end if;

  insert into events (campus_id, title, starts_at, duration_minutes, location, details, organizer, created_by, reminders)
  values (my_campus(), btrim(p_title), p_starts_at, coalesce(p_duration, 60), coalesce(btrim(p_location), ''),
          coalesce(btrim(p_details), ''), (select name from profiles where id = me), me,
          array(select distinct unnest(coalesce(p_reminders, '{}')) order by 1 desc))
  returning id into v_id;
  insert into event_hosts (event_id, club_id) select v_id, unnest(array(select distinct unnest(p_hosts)));
  perform notify_users(array(select u from event_audience(v_id) u where u <> me), 'new_event', p_hosts[1], v_id,
    'New: ' || btrim(p_title), event_when(v_id), 'new:' || v_id);
  perform idem_put(p_request, jsonb_build_object('id', v_id));
  return v_id;
exception when check_violation then
  perform err('validation', 'Check the event details (title length, duration 5 minutes to 24 hours).');
  return null;
end $$;

create or replace function public.cancel_event(p_event uuid) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); e events;
begin
  if not is_event_officer(p_event, me) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  update events set status = 'cancelled' where id = p_event and status <> 'cancelled' returning * into e;
  if e.id is not null and e.starts_at > now() then
    perform notify_users(array(select u from event_audience(p_event) u where u <> me), 'cancelled',
      (select club_id from event_hosts where event_id = p_event limit 1), p_event,
      'Cancelled: ' || e.title, 'This event isn''t happening. ' || coalesce(event_when(p_event), ''), 'cancel:' || p_event);
  end if;
end $$;

-- Scheduled by pg_cron every 5 minutes: event reminders and "rate this event" prompts.
create function public.send_due_notifications() returns int
language plpgsql security definer set search_path = public as $$
declare n int := 0; r record;
begin
  for r in
    select e.id, e.title, x.off, (select h.club_id from event_hosts h where h.event_id = e.id limit 1) as club_id
      from events e cross join lateral unnest(e.reminders) as x(off)
     where e.status <> 'cancelled'
       and e.starts_at > now() and e.starts_at < now() + interval '15 days'
       and now() >= e.starts_at - make_interval(mins => x.off)
       and now() <  e.starts_at - make_interval(mins => x.off) + interval '20 minutes'   -- late RSVPs don't get stale reminders
       and e.created_at <= e.starts_at - make_interval(mins => x.off) + interval '20 minutes'
  loop
    n := n + notify_users(array(select event_audience(r.id)), 'reminder', r.club_id, r.id,
                          r.title || ' starts ' || reminder_label(r.off), event_when(r.id), 'rem:' || r.id || ':' || r.off);
  end loop;

  for r in
    select e.id, e.title, (select h.club_id from event_hosts h where h.event_id = e.id limit 1) as club_id
      from events e
     where e.status <> 'cancelled'
       and now() >= e.starts_at + make_interval(mins => e.duration_minutes + 15)
       and now() <  e.starts_at + make_interval(mins => e.duration_minutes) + interval '1 day'
  loop
    n := n + notify_users(array(
               select a.user_id from attendance a where a.event_id = r.id and a.removed_at is null and a.user_id is not null
                  and not exists (select 1 from event_ratings x where x.event_id = r.id and x.user_id = a.user_id)),
             'rating', r.club_id, r.id, 'How was ' || r.title || '?',
             'Tap to give it 1–5 stars. It''s anonymous: officers only see the average.', 'rate:' || r.id);
  end loop;

  delete from notifications where created_at < now() - interval '120 days';
  return n;
end $$;

-- ───────────────────────────── Ratings ─────────────────────────────
create function public.rate_event(p_event uuid, p_stars int) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); e events;
begin
  select * into e from events where id = p_event;
  if not found then perform err('not_found', 'That event no longer exists.'); end if;
  if p_stars not between 1 and 5 then perform err('validation', 'Pick 1 to 5 stars.'); end if;
  if not exists (select 1 from attendance where event_id = p_event and user_id = me and removed_at is null) then
    perform err('forbidden', 'Only people who checked in can rate this event.');
  end if;
  if now() < e.starts_at + make_interval(mins => e.duration_minutes) - interval '10 minutes' then
    perform err('validation', 'You can rate it once it''s over.');
  end if;
  if now() > e.starts_at + make_interval(mins => e.duration_minutes) + interval '7 days' then
    perform err('validation', 'Ratings close a week after the event.');
  end if;
  insert into event_ratings (event_id, user_id, stars) values (p_event, me, p_stars)
  on conflict (event_id, user_id) do update set stars = excluded.stars, created_at = now();
  update notifications set acted_at = now(), read_at = coalesce(read_at, now()) where user_id = me and dedupe = 'rate:' || p_event;
end $$;

create function public.my_rating(p_event uuid) returns int
language sql stable security definer set search_path = public as $$
  select stars::int from event_ratings where event_id = p_event and user_id = auth.uid()
$$;

-- ───────────────────────────── Officer data ─────────────────────────────
create function public.event_stats(p_event uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb; n_ratings int;
begin
  if not is_event_officer(p_event, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  select count(*) into n_ratings from event_ratings where event_id = p_event;
  select jsonb_build_object(
    'rsvps',      (select count(*) from rsvps where event_id = p_event),
    'checked_in', (select count(*) from attendance where event_id = p_event and removed_at is null),
    'showed',     (select count(*) from attendance a join rsvps r on r.event_id = a.event_id and r.user_id = a.user_id
                    where a.event_id = p_event and a.removed_at is null),
    'guests',     (select count(*) from attendance where event_id = p_event and removed_at is null and user_id is null),
    'ratings',    n_ratings,
    'rating_avg', case when n_ratings >= 3 then (select round(avg(stars), 1) from event_ratings where event_id = p_event) end,
    'rating_dist', case when n_ratings >= 3 then (select jsonb_agg(c order by s) from (
                     select s, (select count(*) from event_ratings where event_id = p_event and stars = s) c
                       from generate_series(1, 5) s) d) end,
    'rsvp_list',  coalesce((select jsonb_agg(jsonb_build_object('name', p.name,
                     'checked_in', exists (select 1 from attendance a where a.event_id = p_event and a.user_id = r.user_id and a.removed_at is null))
                     order by p.name) from rsvps r join profiles p on p.id = r.user_id where r.event_id = p_event), '[]'::jsonb)
  ) into v;
  return v;
end $$;

-- Everything an officer team needs: per-event numbers and every member ranked by how often they show up.
-- Officers are listed but flagged, so rankings and "top supporters" can leave the e-board out.
create function public.club_insights(p_club uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if not is_club_officer(p_club, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  with ev as (
    select e.id, e.title, e.starts_at, e.status,
           (select count(*) from rsvps r where r.event_id = e.id) as rsvps,
           (select count(*) from attendance a where a.event_id = e.id and a.removed_at is null) as checked_in,
           (select count(*) from attendance a join rsvps r on r.event_id = a.event_id and r.user_id = a.user_id
             where a.event_id = e.id and a.removed_at is null) as showed,
           (select count(*) from event_ratings x where x.event_id = e.id) as ratings,
           (select round(avg(stars), 1) from event_ratings x where x.event_id = e.id) as avg_raw
      from events e join event_hosts h on h.event_id = e.id where h.club_id = p_club
  ),
  past as (select * from ev where status <> 'cancelled' and starts_at < now()),
  mem as (
    select m.user_id, p.name, p.email, p.major, p.class_year, m.role, m.officer_title, m.created_at as joined_at, m.paused_until,
           (select count(*) from past where past.starts_at >= m.created_at) as eligible,
           (select count(*) from attendance a join past on past.id = a.event_id where a.user_id = m.user_id and a.removed_at is null) as attended,
           (select count(*) from rsvps r join ev on ev.id = r.event_id where r.user_id = m.user_id) as rsvps,
           (select max(past.starts_at) from attendance a join past on past.id = a.event_id
             where a.user_id = m.user_id and a.removed_at is null) as last_seen,
           (select count(*) from (select past.id from past where past.starts_at >= m.created_at order by past.starts_at desc limit 3) l
             where not exists (select 1 from attendance a where a.event_id = l.id and a.user_id = m.user_id and a.removed_at is null)) as missed_last3,
           (select max(n.created_at) from notifications n where n.user_id = m.user_id and n.club_id = p_club and n.kind = 'nudge') as nudged_at
      from memberships m join profiles p on p.id = m.user_id
     where m.club_id = p_club and m.status = 'active'
  )
  select jsonb_build_object(
    'events', coalesce((select jsonb_agg(jsonb_build_object('id', id, 'title', title, 'starts_at', starts_at, 'status', status,
                 'rsvps', rsvps, 'checked_in', checked_in, 'showed', showed, 'ratings', ratings,
                 'rating_avg', case when ratings >= 3 then avg_raw end) order by starts_at desc) from ev), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', user_id, 'name', name, 'email', email, 'major', major,
                 'class_year', class_year, 'role', role, 'title', officer_title, 'is_officer', role = 'officer',
                 'joined_at', joined_at, 'eligible', eligible, 'attended', attended, 'rsvps', rsvps, 'last_seen', last_seen,
                 'nudged_at', nudged_at, 'busy', paused_until > now(),
                 'fading', role <> 'officer' and joined_at < now() - interval '21 days' and eligible >= 3 and missed_last3 = 3
                           and coalesce(paused_until, '-infinity') < now())
               order by (role = 'officer'), attended desc, rsvps desc, name) from mem), '[]'::jsonb)
  ) into v;
  return v;
end $$;

-- "Still interested?" — a friendly check-in, at most once a month per member per club.
create function public.nudge_members(p_club uuid, p_users uuid[]) returns int
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); v_name text := (select name from clubs where id = p_club);
begin
  if not is_club_officer(p_club, me) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  return notify_users(array(
      select m.user_id from memberships m where m.club_id = p_club and m.user_id = any (p_users)
         and m.status = 'active' and m.role <> 'officer'
         and not exists (select 1 from notifications n where n.user_id = m.user_id and n.club_id = p_club
                                                         and n.kind = 'nudge' and n.created_at > now() - interval '30 days')),
    'nudge', p_club, null, 'We miss you at ' || v_name,
    'No pressure. If you''re busy, you can stay in and we''ll keep you posted. If it''s not for you anymore, you can leave anytime, no hard feelings.',
    'nudge:' || p_club || ':' || to_char(now(), 'YYYY-MM-DD'));
end $$;

create function public.respond_nudge(p_notification uuid, p_choice text) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); n notifications;
begin
  select * into n from notifications where id = p_notification and user_id = me and kind = 'nudge';
  if not found then perform err('not_found', 'That message is gone.'); end if;
  if p_choice = 'busy' then
    update memberships set paused_until = now() + interval '60 days' where club_id = n.club_id and user_id = me;
  elsif p_choice = 'leave' then
    delete from memberships where club_id = n.club_id and user_id = me and role <> 'officer';
  elsif p_choice <> 'stay' then
    perform err('validation', 'Pick an option.');
  end if;
  update notifications set acted_at = now(), read_at = coalesce(read_at, now()) where id = p_notification;
end $$;

-- Officers' one-way announcements (not a chat). Goes to members who haven't muted the club.
create function public.send_announcement(p_club uuid, p_title text, p_body text) returns int
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user();
begin
  if not is_club_officer(p_club, me) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  if char_length(btrim(coalesce(p_title, ''))) < 2 then perform err('validation', 'Add a short title.'); end if;
  if (select count(*) from notifications where club_id = p_club and kind = 'announcement' and created_at > now() - interval '1 day'
        and user_id = me) >= 5 then
    perform err('validation', 'That''s 5 announcements today. Members mute clubs that post too much.');
  end if;
  return notify_users(array(
      select m.user_id from memberships m where m.club_id = p_club and m.status = 'active'
         and (m.notify <> 'none' or m.user_id = me)
         and not exists (select 1 from club_blocks b where b.user_id = m.user_id and b.club_id = p_club)),
    'announcement', p_club, null, (select name from clubs where id = p_club) || ': ' || btrim(p_title), btrim(coalesce(p_body, '')),
    'ann:' || gen_random_uuid());
end $$;

-- ───────────────────────────── Members ─────────────────────────────
create function public.club_leaderboard(p_club uuid) returns table (rank int, name text, attended int, is_me boolean)
language plpgsql stable security definer set search_path = public as $$
declare me uuid := require_user();
begin
  if not is_club_member(p_club, me) then perform err('forbidden', 'Join the club to see its leaderboard.'); end if;
  return query
    select (rank() over (order by x.cnt desc))::int, p.name, x.cnt::int, p.id = me
      from (select m.user_id, count(a.id) as cnt
              from memberships m
              left join (attendance a join event_hosts h on h.event_id = a.event_id and h.club_id = p_club)
                     on a.user_id = m.user_id and a.removed_at is null
             where m.club_id = p_club and m.status = 'active' and m.role <> 'officer'
             group by m.user_id) x
      join profiles p on p.id = x.user_id
     where x.cnt > 0 and (p.leaderboard or p.id = me)
     order by x.cnt desc, p.name limit 25;
end $$;

-- Students who share your interests and chose to be findable. You only see others while you're findable too.
create function public.people_to_meet() returns table (user_id uuid, name text, major text, class_year text, pronouns text, bio text,
                                                       interests text[], shared text[], email text, phone text, linkedin text, common_clubs int)
language sql stable security definer set search_path = public as $$
  select * from (
    select p.id, p.name, p.major, p.class_year, p.pronouns, p.bio, p.interests,
           array(select unnest(p.interests) intersect select unnest(me.interests)) as shared,
           case when p.share_email then p.email else '' end as email,
           case when p.share_phone then p.phone else '' end as phone,
           case when p.share_linkedin then p.linkedin else '' end as linkedin,
           (select count(*) from memberships a join memberships b on a.club_id = b.club_id
             where a.user_id = p.id and b.user_id = me.id and a.status = 'active' and b.status = 'active')::int as common
      from profiles p, profiles me
     where me.id = auth.uid() and me.discoverable and p.id <> me.id and p.campus_id = me.campus_id
       and p.discoverable and p.onboarded_at is not null and p.interests && me.interests
  ) t order by cardinality(t.shared) desc, t.common desc, t.name limit 60
$$;

create function public.mark_notifications_read(p_ids uuid[] default null) returns void
language sql security definer set search_path = public as $$
  update notifications set read_at = now()
   where user_id = auth.uid() and read_at is null and (p_ids is null or id = any (p_ids))
$$;

-- ───────────────────────────── Club logo storage ─────────────────────────────
create function public.try_uuid(t text) returns uuid
language plpgsql immutable as $$ begin return t::uuid; exception when others then return null; end $$;

do $storage$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('club-logos', 'club-logos', true, 1048576, array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do nothing;
    execute $p$create policy club_logos_insert on storage.objects for insert to authenticated with check (
      bucket_id = 'club-logos' and public.is_club_officer(public.try_uuid((storage.foldername(name))[1]), auth.uid()))$p$;
    execute $p$create policy club_logos_update on storage.objects for update to authenticated using (
      bucket_id = 'club-logos' and public.is_club_officer(public.try_uuid((storage.foldername(name))[1]), auth.uid()))$p$;
    execute $p$create policy club_logos_delete on storage.objects for delete to authenticated using (
      bucket_id = 'club-logos' and public.is_club_officer(public.try_uuid((storage.foldername(name))[1]), auth.uid()))$p$;
  end if;
end $storage$;

-- ───────────────────────────── Scheduler ─────────────────────────────
do $cron$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.schedule('vnua-notifications', '*/5 * * * *', 'select public.send_due_notifications()');
  end if;
end $cron$;

-- ───────────────────────────── Grants ─────────────────────────────
revoke all on all tables in schema public from anon;
-- Supabase also grants every new function to "authenticated" by default. Start from nothing and allow a whitelist,
-- so server-only helpers (notify_users, send_due_notifications, idem_put, …) can't be called from the app.
revoke all on all functions in schema public from anon, authenticated, public;
revoke insert, update, delete, truncate on all tables in schema public from authenticated;
grant execute on function
  public.join_club, public.update_contact, public.leave_club, public.join_requests, public.review_join_request,
  public.create_club, public.set_rsvp, public.issue_pass, public.search_attendees, public.check_in,
  public.correct_attendance, public.block_club, public.report_content, public.delete_account,
  public.create_event, public.cancel_event,
  public.my_campus, public.is_club_member, public.is_club_officer, public.is_event_officer, public.is_platform_admin,
  public.can_see_event
to authenticated;
grant select on public.club_invites, public.notifications, public.club_officers to authenticated;
revoke all on public.event_ratings from authenticated;
grant execute on function
  public.save_profile, public.create_club, public.update_club, public.set_club_logo,
  public.invite_officer, public.revoke_invite, public.respond_invite, public.update_officer_info, public.remove_officer,
  public.join_club, public.update_notify, public.review_join_request, public.create_event, public.cancel_event,
  public.rate_event, public.my_rating, public.event_stats, public.club_insights, public.nudge_members, public.respond_nudge,
  public.send_announcement, public.club_leaderboard, public.people_to_meet, public.mark_notifications_read,
  -- used inside RLS policies / views / storage policies, so the caller needs execute:
  public.my_email, public.can_see_club, public.position_rank, public.try_uuid
to authenticated;
