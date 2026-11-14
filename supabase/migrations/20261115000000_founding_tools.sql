-- v3: tools for getting a new club off the ground.
--   * Public preview of published clubs/events, so a shared link works before someone signs up
--   * "New here?" info on events, and editing events (location, time, details)
--   * Member preferences per club: involvement (updates / attend / organize) and recognition-contact consent
--   * Profile: "I can help with" / "I'm looking for"
--   * Officer follow-up tasks (owner, due date, linked event)
--   * Availability polls ("Which of these times works?") that turn into an event
--   * Optional "keep / change" feedback with ratings (shown to officers only from 3+ responses)

-- ───────────────────────────── Columns ─────────────────────────────
alter table public.profiles
  add column help_with   text[] not null default '{}' check (cardinality(help_with) <= 6),
  add column looking_for text[] not null default '{}' check (cardinality(looking_for) <= 4);

alter table public.memberships
  add column involvement    text not null default 'attend' check (involvement in ('updates', 'attend', 'organize')),
  add column recognition_ok boolean not null default false;    -- OK to be contacted / listed for the recognition request

alter table public.events add column newcomer jsonb not null default '{}'::jsonb;

alter table public.event_ratings
  add column keep_text   text check (char_length(keep_text) <= 500),
  add column change_text text check (char_length(change_text) <= 500);

alter table public.notifications drop constraint notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in (
  'reminder', 'new_event', 'cancelled', 'rating', 'nudge', 'invite', 'approved', 'team_complete', 'announcement',
  'event_changed', 'poll', 'task'));

-- ───────────────────────────── Tables ─────────────────────────────
create table public.club_tasks (
  id         uuid primary key default gen_random_uuid(),
  club_id    uuid not null references public.clubs (id) on delete cascade,
  title      text not null check (char_length(btrim(title)) between 2 and 140),
  owner_id   uuid references public.profiles (id) on delete set null,
  due_on     date,
  event_id   uuid references public.events (id) on delete set null,
  done_at    timestamptz,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now()
);
create index on public.club_tasks (club_id) where done_at is null;

create table public.polls (
  id               uuid primary key default gen_random_uuid(),
  club_id          uuid not null references public.clubs (id) on delete cascade,
  title            text not null check (char_length(btrim(title)) between 2 and 140),
  duration_minutes int not null default 60 check (duration_minutes between 5 and 1440),
  location         text not null default '' check (char_length(location) <= 140),
  deadline         timestamptz not null,
  created_by       uuid references public.profiles (id) on delete set null,
  created_at       timestamptz not null default now(),
  closed_at        timestamptz,
  event_id         uuid references public.events (id) on delete set null
);
create index on public.polls (club_id);
create table public.poll_slots (
  id        uuid primary key default gen_random_uuid(),
  poll_id   uuid not null references public.polls (id) on delete cascade,
  starts_at timestamptz not null
);
create index on public.poll_slots (poll_id);
create table public.poll_votes (
  slot_id uuid not null references public.poll_slots (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  answer  text not null check (answer in ('yes', 'maybe', 'no')),
  primary key (slot_id, user_id)
);

alter table public.club_tasks enable row level security;
alter table public.polls      enable row level security;
alter table public.poll_slots enable row level security;
alter table public.poll_votes enable row level security;
create policy tasks_officers on public.club_tasks for select using (public.is_club_officer(club_id, auth.uid()));
create policy polls_members on public.polls for select using (public.is_club_member(club_id, auth.uid()));
create function public.can_see_poll(p_poll uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from polls where id = p_poll and is_club_member(club_id, auth.uid()))
$$;
create policy poll_slots_members on public.poll_slots for select using (public.can_see_poll(poll_id));
create policy poll_votes_self on public.poll_votes for select using (user_id = auth.uid());   -- individual answers stay private

-- ───────────────────────────── Helpers ─────────────────────────────
-- Keeps only the known "New here?" fields, trimmed and capped.
create function public.clean_newcomer(p jsonb) returns jsonb
language sql immutable as $$
  select coalesce(jsonb_object_agg(k, left(btrim(v), 300)), '{}'::jsonb)
    from jsonb_each_text(case when jsonb_typeof(p) = 'object' then p else '{}'::jsonb end) t(k, v)
   where k in ('who', 'experience', 'bring', 'cost', 'meet', 'happens', 'contact') and btrim(v) <> ''
$$;

-- ───────────────────────────── Public previews (shared links) ─────────────────────────────
-- Only published clubs. Officers appear by first name + position; no emails, no member names.
create function public.club_preview(p_club uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'id', c.id, 'name', c.name, 'blurb', c.blurb, 'about', c.about, 'interest', c.interest, 'logo_url', c.logo_url,
    'accent_hex', c.accent_hex, 'monogram', c.monogram, 'recognition', c.recognition, 'requires_approval', c.requires_approval,
    'campus', (select name from campuses where id = c.campus_id),
    'members', (select count(*) from memberships where club_id = c.id and status = 'active'),
    'officers', coalesce((select jsonb_agg(jsonb_build_object('name', split_part(p.name, ' ', 1), 'title', m.officer_title)
                                           order by position_rank(m.officer_title))
                            from memberships m join profiles p on p.id = m.user_id
                           where m.club_id = c.id and m.role = 'officer' and m.status = 'active'), '[]'::jsonb),
    'next_event', (select jsonb_build_object('id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'location', e.location)
                     from events e join event_hosts h on h.event_id = e.id
                    where h.club_id = c.id and e.status <> 'cancelled' and e.starts_at > now()
                    order by e.starts_at limit 1))
    from clubs c where c.id = p_club and c.is_published
$$;

create function public.event_preview(p_event uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'duration_minutes', e.duration_minutes,
           'location', e.location, 'details', e.details, 'status', e.status, 'newcomer', e.newcomer,
           'hosts', (select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name)) from event_hosts h join clubs c on c.id = h.club_id
                      where h.event_id = e.id and c.is_published))
    from events e
   where e.id = p_event
     and exists (select 1 from event_hosts h join clubs c on c.id = h.club_id where h.event_id = e.id and c.is_published)
$$;

-- ───────────────────────────── Profiles ─────────────────────────────
create function public.save_profile_extras(p_help_with text[], p_looking_for text[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  if cardinality(coalesce(p_help_with, '{}')) > 6 or cardinality(coalesce(p_looking_for, '{}')) > 4 then
    perform err('validation', 'Pick fewer options.');
  end if;
  update profiles set
    help_with   = array(select distinct left(btrim(x), 40) from unnest(coalesce(p_help_with, '{}')) x where btrim(x) <> ''),
    looking_for = array(select distinct left(btrim(x), 40) from unnest(coalesce(p_looking_for, '{}')) x where btrim(x) <> '')
   where id = require_user();
end $$;

drop function public.people_to_meet();
create function public.people_to_meet() returns table (user_id uuid, name text, major text, class_year text, pronouns text, bio text,
                                                       interests text[], shared text[], email text, phone text, linkedin text,
                                                       common_clubs int, help_with text[], looking_for text[])
language sql stable security definer set search_path = public as $$
  select * from (
    select p.id, p.name, p.major, p.class_year, p.pronouns, p.bio, p.interests,
           array(select unnest(p.interests) intersect select unnest(me.interests)) as shared,
           case when p.share_email then p.email else '' end as email,
           case when p.share_phone then p.phone else '' end as phone,
           case when p.share_linkedin then p.linkedin else '' end as linkedin,
           (select count(*) from memberships a join memberships b on a.club_id = b.club_id
             where a.user_id = p.id and b.user_id = me.id and a.status = 'active' and b.status = 'active')::int as common,
           p.help_with, p.looking_for
      from profiles p, profiles me
     where me.id = auth.uid() and me.discoverable and p.id <> me.id and p.campus_id = me.campus_id
       and p.discoverable and p.onboarded_at is not null and p.interests && me.interests
  ) t order by cardinality(t.shared) desc, t.common desc, t.name limit 60
$$;

-- ───────────────────────────── Membership preferences ─────────────────────────────
drop function public.join_club(uuid, public.member_role, public.contact_pref, uuid, text);
create function public.join_club(p_club uuid, p_role public.member_role, p_contact public.contact_pref, p_request uuid,
                                 p_notify text default 'rsvp', p_involvement text default 'attend', p_recognition_ok boolean default false)
returns jsonb language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); c clubs; m memberships; cached jsonb := idem_get(p_request);
begin
  if cached is not null then return cached; end if;
  if p_role not in ('member', 'founding') then perform err('forbidden_role', 'You can''t give yourself that role.'); end if;
  if coalesce(p_notify, 'rsvp') not in ('all', 'rsvp', 'none') then perform err('validation', 'Pick a notification setting.'); end if;
  if coalesce(p_involvement, 'attend') not in ('updates', 'attend', 'organize') then perform err('validation', 'Pick how involved you want to be.'); end if;
  select * into c from clubs where id = p_club;
  if not found or c.campus_id <> my_campus() or not can_see_club(p_club) then perform err('not_found', 'That club no longer exists.'); end if;
  if exists (select 1 from club_blocks where user_id = me and club_id = p_club) then
    perform err('validation', 'Unblock this club before joining.');
  end if;
  insert into memberships (club_id, user_id, role, status, contact, notify, involvement, recognition_ok)
  values (p_club, me, p_role, (case when c.requires_approval then 'pending' else 'active' end)::membership_status, p_contact,
          coalesce(p_notify, 'rsvp'), coalesce(p_involvement, 'attend'), coalesce(p_recognition_ok, false))
  on conflict (club_id, user_id) do update set contact = excluded.contact, notify = excluded.notify,
                                               involvement = excluded.involvement, recognition_ok = excluded.recognition_ok
  returning * into m;
  return idem_put(p_request, jsonb_build_object('club_id', m.club_id, 'role', m.role, 'status', m.status, 'contact', m.contact,
                                                'notify', m.notify, 'involvement', m.involvement, 'recognition_ok', m.recognition_ok));
end $$;

create function public.update_membership(p_club uuid, p_notify text, p_involvement text, p_recognition_ok boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_notify not in ('all', 'rsvp', 'none') or p_involvement not in ('updates', 'attend', 'organize') then
    perform err('validation', 'Pick an option.');
  end if;
  update memberships set notify = p_notify, involvement = p_involvement, recognition_ok = coalesce(p_recognition_ok, false),
         role = case when role = 'member' and p_involvement = 'organize' then 'founding'::member_role else role end
   where club_id = p_club and user_id = require_user();
  if not found then perform err('not_found', 'You''re not in this club.'); end if;
end $$;

-- ───────────────────────────── Events ─────────────────────────────
drop function public.create_event(uuid[], text, timestamptz, int, text, text, uuid, int[]);
create function public.create_event(p_hosts uuid[], p_title text, p_starts_at timestamptz, p_duration int,
                                    p_location text, p_details text, p_request uuid, p_reminders int[] default '{1440,120}',
                                    p_newcomer jsonb default '{}')
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

  insert into events (campus_id, title, starts_at, duration_minutes, location, details, organizer, created_by, reminders, newcomer)
  values (my_campus(), btrim(p_title), p_starts_at, coalesce(p_duration, 60), coalesce(btrim(p_location), ''),
          coalesce(btrim(p_details), ''), (select name from profiles where id = me), me,
          array(select distinct unnest(coalesce(p_reminders, '{}')) order by 1 desc), clean_newcomer(p_newcomer))
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

-- Edit an event. Moving the start marks it "rescheduled", keeps the old time, and tells everyone who'd hear about it.
create function public.update_event(p_event uuid, p_title text, p_starts_at timestamptz, p_duration int, p_location text,
                                    p_details text, p_reminders int[], p_newcomer jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); e events;
begin
  if not is_event_officer(p_event, me) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  select * into e from events where id = p_event;
  if e.status = 'cancelled' then perform err('validation', 'This event was cancelled.'); end if;
  if char_length(btrim(coalesce(p_title, ''))) < 2 then perform err('validation', 'Give the event a title.'); end if;
  if p_starts_at <> e.starts_at and p_starts_at < now() - interval '1 hour' then perform err('validation', 'Pick a start time in the future.'); end if;
  if not coalesce(p_reminders, '{}') <@ array[20160, 10080, 4320, 1440, 120, 60, 30] then
    perform err('validation', 'Pick reminder times from the list.');
  end if;
  update events set title = btrim(p_title), starts_at = p_starts_at, duration_minutes = coalesce(p_duration, duration_minutes),
         location = coalesce(btrim(p_location), ''), details = coalesce(btrim(p_details), ''),
         reminders = array(select distinct unnest(coalesce(p_reminders, '{}')) order by 1 desc), newcomer = clean_newcomer(p_newcomer),
         status = case when p_starts_at <> e.starts_at then 'rescheduled'::event_status else status end,
         previous_start = case when p_starts_at <> e.starts_at then e.starts_at else previous_start end
   where id = p_event;
  if p_starts_at <> e.starts_at or coalesce(btrim(p_location), '') <> e.location then
    perform notify_users(array(select u from event_audience(p_event) u where u <> me), 'event_changed',
      (select club_id from event_hosts where event_id = p_event limit 1), p_event,
      'Changed: ' || btrim(p_title), 'Now ' || coalesce(event_when(p_event), ''),
      'chg:' || p_event || ':' || extract(epoch from p_starts_at)::bigint || ':' || md5(coalesce(btrim(p_location), '')));
  end if;
exception when check_violation then
  perform err('validation', 'Check the event details (title length, duration 5 minutes to 24 hours).');
end $$;

-- ───────────────────────────── Ratings + feedback ─────────────────────────────
drop function public.rate_event(uuid, int);
create function public.rate_event(p_event uuid, p_stars int, p_keep text default null, p_change text default null) returns void
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
  insert into event_ratings (event_id, user_id, stars, keep_text, change_text)
  values (p_event, me, p_stars, nullif(left(btrim(coalesce(p_keep, '')), 500), ''), nullif(left(btrim(coalesce(p_change, '')), 500), ''))
  on conflict (event_id, user_id) do update set stars = excluded.stars,
     keep_text = coalesce(excluded.keep_text, event_ratings.keep_text), change_text = coalesce(excluded.change_text, event_ratings.change_text),
     created_at = now();
  update notifications set acted_at = now(), read_at = coalesce(read_at, now()) where user_id = me and dedupe = 'rate:' || p_event;
end $$;

create or replace function public.event_stats(p_event uuid) returns jsonb
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
    'first_timers', (select count(*) from attendance a where a.event_id = p_event and a.removed_at is null and a.user_id is not null
                      and not exists (select 1 from attendance b join events eb on eb.id = b.event_id
                                       where b.user_id = a.user_id and b.removed_at is null
                                         and eb.starts_at < (select starts_at from events where id = p_event))),
    'ratings',    n_ratings,
    'rating_avg', case when n_ratings >= 3 then (select round(avg(stars), 1) from event_ratings where event_id = p_event) end,
    'rating_dist', case when n_ratings >= 3 then (select jsonb_agg(c order by s) from (
                     select s, (select count(*) from event_ratings where event_id = p_event and stars = s) c
                       from generate_series(1, 5) s) d) end,
    -- Written feedback: only once 3+ people responded, shuffled, never with names.
    'keep',   case when n_ratings >= 3 then (select coalesce(jsonb_agg(keep_text order by random()), '[]'::jsonb) from event_ratings
                                               where event_id = p_event and keep_text is not null) end,
    'change', case when n_ratings >= 3 then (select coalesce(jsonb_agg(change_text order by random()), '[]'::jsonb) from event_ratings
                                               where event_id = p_event and change_text is not null) end,
    'rsvp_list',  coalesce((select jsonb_agg(jsonb_build_object('name', p.name,
                     'checked_in', exists (select 1 from attendance a where a.event_id = p_event and a.user_id = r.user_id and a.removed_at is null))
                     order by p.name) from rsvps r join profiles p on p.id = r.user_id where r.event_id = p_event), '[]'::jsonb)
  ) into v;
  return v;
end $$;

create function public.my_feedback(p_event uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('stars', stars, 'keep', keep_text, 'change', change_text)
    from event_ratings where event_id = p_event and user_id = auth.uid()
$$;

-- ───────────────────────────── Officer insights (adds preferences + recency) ─────────────────────────────
create or replace function public.club_insights(p_club uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if not is_club_officer(p_club, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  with ev as (
    select e.id, e.title, e.starts_at, e.status, e.location, e.newcomer,
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
    select m.user_id, p.name, p.email, p.major, p.class_year, p.help_with, m.role, m.officer_title, m.created_at as joined_at,
           m.paused_until, m.involvement, m.recognition_ok,
           (select count(*) from past where past.starts_at >= m.created_at) as eligible,
           (select count(*) from attendance a join past on past.id = a.event_id where a.user_id = m.user_id and a.removed_at is null) as attended,
           (select count(*) from attendance a join past on past.id = a.event_id where a.user_id = m.user_id and a.removed_at is null
               and past.starts_at > now() - interval '30 days') as attended_30,
           (select count(*) from rsvps r join ev on ev.id = r.event_id where r.user_id = m.user_id) as rsvps,
           (select min(past.starts_at) from attendance a join past on past.id = a.event_id
             where a.user_id = m.user_id and a.removed_at is null) as first_seen,
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
                 'location', location, 'has_newcomer', newcomer <> '{}'::jsonb,
                 'rsvps', rsvps, 'checked_in', checked_in, 'showed', showed, 'ratings', ratings,
                 'rating_avg', case when ratings >= 3 then avg_raw end) order by starts_at desc) from ev), '[]'::jsonb),
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', user_id, 'name', name, 'email', email, 'major', major,
                 'class_year', class_year, 'help_with', help_with, 'role', role, 'title', officer_title, 'is_officer', role = 'officer',
                 'involvement', involvement, 'recognition_ok', recognition_ok,
                 'joined_at', joined_at, 'eligible', eligible, 'attended', attended, 'attended_30', attended_30, 'rsvps', rsvps,
                 'first_seen', first_seen, 'last_seen', last_seen, 'nudged_at', nudged_at, 'busy', paused_until > now(),
                 'fading', role <> 'officer' and joined_at < now() - interval '21 days' and eligible >= 3 and missed_last3 = 3
                           and coalesce(paused_until, '-infinity') < now())
               order by (role = 'officer'), attended desc, rsvps desc, name) from mem), '[]'::jsonb)
  ) into v;
  return v;
end $$;

-- ───────────────────────────── Tasks ─────────────────────────────
create function public.save_task(p_task uuid, p_club uuid, p_title text, p_owner uuid, p_due date, p_event uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); v_id uuid; v_old uuid;
begin
  if p_task is not null then
    select club_id, owner_id into p_club, v_old from club_tasks where id = p_task;
  end if;
  if p_club is null or not is_club_officer(p_club, me) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  if p_owner is not null and not is_club_officer(p_club, p_owner) then perform err('validation', 'Pick an officer to own it.'); end if;
  if p_event is not null and not exists (select 1 from event_hosts where event_id = p_event and club_id = p_club) then
    perform err('validation', 'That event isn''t this club''s.');
  end if;
  if char_length(btrim(coalesce(p_title, ''))) < 2 then perform err('validation', 'Describe the task.'); end if;
  if p_task is null then
    insert into club_tasks (club_id, title, owner_id, due_on, event_id, created_by)
    values (p_club, left(btrim(p_title), 140), p_owner, p_due, p_event, me) returning id into v_id;
  else
    update club_tasks set title = left(btrim(p_title), 140), owner_id = p_owner, due_on = p_due, event_id = p_event
     where id = p_task returning id into v_id;
  end if;
  if p_owner is not null and p_owner <> me and p_owner is distinct from v_old then
    perform notify_users(array[p_owner], 'task', p_club, p_event, 'New task: ' || left(btrim(p_title), 100),
      coalesce('Due ' || to_char(p_due, 'FMMon FMDD'), 'No due date') || ' · from ' || (select name from profiles where id = me),
      'task:' || v_id || ':' || p_owner);
  end if;
  return v_id;
end $$;

create function public.set_task_done(p_task uuid, p_done boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_club uuid := (select club_id from club_tasks where id = p_task);
begin
  if v_club is null or not is_club_officer(v_club, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  update club_tasks set done_at = case when p_done then coalesce(done_at, now()) end where id = p_task;
end $$;

create function public.delete_task(p_task uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_club uuid := (select club_id from club_tasks where id = p_task);
begin
  if v_club is null or not is_club_officer(v_club, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  delete from club_tasks where id = p_task;
end $$;

-- ───────────────────────────── Availability polls ─────────────────────────────
create function public.create_poll(p_club uuid, p_title text, p_slots timestamptz[], p_duration int, p_location text, p_deadline timestamptz)
returns uuid language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); v_id uuid; n int := cardinality(coalesce(p_slots, '{}'));
begin
  if not is_club_officer(p_club, me) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  if n < 2 or n > 6 then perform err('validation', 'Offer 2 to 6 times.'); end if;
  if exists (select 1 from unnest(p_slots) s where s < now()) then perform err('validation', 'All the times need to be in the future.'); end if;
  if p_deadline < now() + interval '30 minutes' or p_deadline > (select min(s) from unnest(p_slots) s) then
    perform err('validation', 'Set the reply deadline before the earliest time.');
  end if;
  if (select count(*) from polls where club_id = p_club and closed_at is null and deadline > now()) >= 5 then
    perform err('validation', 'Close an open poll first.');
  end if;
  insert into polls (club_id, title, duration_minutes, location, deadline, created_by)
  values (p_club, btrim(p_title), coalesce(p_duration, 60), coalesce(btrim(p_location), ''), p_deadline, me) returning id into v_id;
  insert into poll_slots (poll_id, starts_at) select v_id, s from (select distinct unnest(p_slots) s) x;
  perform notify_users(array(
      select m.user_id from memberships m where m.club_id = p_club and m.status = 'active' and m.notify <> 'none' and m.user_id <> me
         and not exists (select 1 from club_blocks b where b.user_id = m.user_id and b.club_id = p_club)),
    'poll', p_club, null, 'When works for you? ' || btrim(p_title),
    'Pick the times you could make. Reply by ' || to_char(p_deadline at time zone (select c.timezone from campuses c join clubs k on k.campus_id = c.id where k.id = p_club), 'FMDy FMMon FMDD, FMHH12:MI AM') || '.',
    'poll:' || v_id);
  return v_id;
exception when check_violation then
  perform err('validation', 'Give the poll a title (2–140 characters).');
  return null;
end $$;

create function public.vote_poll(p_slot uuid, p_answer text) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); p polls;
begin
  select pl.* into p from polls pl join poll_slots s on s.poll_id = pl.id where s.id = p_slot;
  if not found or not is_club_member(p.club_id, me) then perform err('not_found', 'That poll is gone.'); end if;
  if p.closed_at is not null or p.deadline < now() then perform err('validation', 'This poll is closed.'); end if;
  if p_answer not in ('yes', 'maybe', 'no') then perform err('validation', 'Pick yes, maybe or no.'); end if;
  insert into poll_votes (slot_id, user_id, answer) values (p_slot, me, p_answer)
  on conflict (slot_id, user_id) do update set answer = excluded.answer;
end $$;

-- Counts per time for officers. Individual answers are never shown.
create function public.poll_results(p_poll uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare p polls;
begin
  select * into p from polls where id = p_poll;
  if not found or not is_club_officer(p.club_id, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  return jsonb_build_object(
    'responders', (select count(distinct v.user_id) from poll_votes v join poll_slots s on s.id = v.slot_id where s.poll_id = p_poll),
    'members', (select count(*) from memberships where club_id = p.club_id and status = 'active'),
    'slots', (select jsonb_agg(jsonb_build_object('id', s.id, 'starts_at', s.starts_at,
                'yes', (select count(*) from poll_votes v where v.slot_id = s.id and v.answer = 'yes'),
                'maybe', (select count(*) from poll_votes v where v.slot_id = s.id and v.answer = 'maybe'),
                'no', (select count(*) from poll_votes v where v.slot_id = s.id and v.answer = 'no')) order by s.starts_at)
                from poll_slots s where s.poll_id = p_poll));
end $$;

-- Turn the chosen time into a real event (same rules as create_event) and close the poll.
-- Everyone who said yes or maybe to that time hears about it.
create function public.schedule_poll(p_poll uuid, p_slot uuid, p_request uuid) returns uuid
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user(); p polls; s poll_slots; v_event uuid;
begin
  select * into p from polls where id = p_poll;
  if not found or not is_club_officer(p.club_id, me) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  if p.event_id is not null then return p.event_id; end if;
  select * into s from poll_slots where id = p_slot and poll_id = p_poll;
  if not found then perform err('not_found', 'That time isn''t part of this poll.'); end if;
  v_event := create_event(array[p.club_id], p.title, s.starts_at, p.duration_minutes, p.location, '', p_request);
  update polls set closed_at = now(), event_id = v_event where id = p_poll;
  perform notify_users(array(select v.user_id from poll_votes v where v.slot_id = p_slot and v.answer in ('yes', 'maybe') and v.user_id <> me),
    'new_event', p.club_id, v_event, 'It''s on: ' || p.title, event_when(v_event), 'new:' || v_event);
  return v_event;
end $$;

create function public.close_poll(p_poll uuid) returns void
language plpgsql security definer set search_path = public as $$
declare v_club uuid := (select club_id from polls where id = p_poll);
begin
  if v_club is null or not is_club_officer(v_club, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  update polls set closed_at = coalesce(closed_at, now()) where id = p_poll;
end $$;

-- ───────────────────────────── Grants (whitelist) ─────────────────────────────
revoke all on all tables in schema public from anon;
revoke all on all functions in schema public from anon, authenticated, public;
revoke insert, update, delete, truncate on all tables in schema public from authenticated;
grant select on public.club_tasks, public.polls, public.poll_slots, public.poll_votes to authenticated;
grant execute on function public.club_preview, public.event_preview to anon, authenticated;
grant execute on function
  -- init + officer events
  public.join_club, public.update_contact, public.leave_club, public.join_requests, public.review_join_request,
  public.create_club, public.set_rsvp, public.issue_pass, public.search_attendees, public.check_in,
  public.correct_attendance, public.block_club, public.report_content, public.delete_account,
  public.create_event, public.cancel_event,
  -- v2
  public.save_profile, public.update_club, public.set_club_logo,
  public.invite_officer, public.revoke_invite, public.respond_invite, public.update_officer_info, public.remove_officer,
  public.update_notify, public.rate_event, public.my_rating, public.event_stats, public.club_insights, public.nudge_members,
  public.respond_nudge, public.send_announcement, public.club_leaderboard, public.people_to_meet, public.mark_notifications_read,
  -- v3
  public.save_profile_extras, public.update_membership, public.update_event, public.my_feedback,
  public.save_task, public.set_task_done, public.delete_task,
  public.create_poll, public.vote_poll, public.poll_results, public.schedule_poll, public.close_poll,
  -- used inside RLS policies / views / storage policies
  public.my_campus, public.is_club_member, public.is_club_officer, public.is_event_officer, public.is_platform_admin,
  public.can_see_event, public.my_email, public.can_see_club, public.position_rank, public.try_uuid, public.can_see_poll
to authenticated;
