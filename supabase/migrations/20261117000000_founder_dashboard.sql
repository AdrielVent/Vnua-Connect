-- Founder dashboard: platform-wide usage data for the app's founder (profiles.is_platform_admin), behind a second check.
--   * The founder signs in normally, then answers a security question. The answer is stored only as a bcrypt hash
--     (pgcrypto) in a table no app user can read, and is set with the service key — it never appears in this repo.
--   * A correct answer unlocks founder data for 12 hours. 5 wrong answers in 15 minutes lock it for 15 minutes.
--   * founder_overview() returns counts, trends, every club's health and every student's activity.

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

create table public.admin_secrets (
  user_id     uuid primary key references public.profiles (id) on delete cascade,
  question    text not null check (char_length(question) between 5 and 200),
  answer_hash text not null,
  updated_at  timestamptz not null default now()
);
create table public.admin_unlocks (
  user_id    uuid primary key references public.profiles (id) on delete cascade,
  expires_at timestamptz not null
);
create table public.admin_attempts (
  user_id uuid not null references public.profiles (id) on delete cascade,
  at      timestamptz not null default now()
);
create index on public.admin_attempts (user_id, at);
alter table public.admin_secrets  enable row level security;
alter table public.admin_unlocks  enable row level security;
alter table public.admin_attempts enable row level security;
-- no policies: never readable by app users

-- Service key only (run once, from a trusted machine). Normalises the answer: trimmed, lower-case.
create function public.set_admin_secret(p_email text, p_question text, p_answer text) returns void
language plpgsql security definer set search_path = public, extensions as $$
declare v_id uuid := (select id from profiles where email = lower(btrim(p_email)));
begin
  if v_id is null then perform err('not_found', 'No account with that email.'); end if;
  if char_length(btrim(coalesce(p_answer, ''))) < 2 then perform err('validation', 'Answer too short.'); end if;
  update profiles set is_platform_admin = true where id = v_id;
  insert into admin_secrets (user_id, question, answer_hash)
  values (v_id, btrim(p_question), crypt(lower(btrim(p_answer)), gen_salt('bf', 10)))
  on conflict (user_id) do update set question = excluded.question, answer_hash = excluded.answer_hash, updated_at = now();
  delete from admin_unlocks where user_id = v_id;
end $$;

create function public.admin_question() returns text
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_platform_admin() then perform err('forbidden', 'Founders only.'); end if;
  return (select question from admin_secrets where user_id = auth.uid());
end $$;

create function public.admin_unlock(p_answer text) returns timestamptz
language plpgsql security definer set search_path = public, extensions as $$
declare me uuid := require_user(); h text; v_exp timestamptz := now() + interval '12 hours';
begin
  if not is_platform_admin() then perform err('forbidden', 'Founders only.'); end if;
  if (select count(*) from admin_attempts where user_id = me and at > now() - interval '15 minutes') >= 5 then
    perform err('validation', 'Too many tries. Wait 15 minutes.');
  end if;
  select answer_hash into h from admin_secrets where user_id = me;
  if h is null or crypt(lower(btrim(coalesce(p_answer, ''))), h) <> h then
    insert into admin_attempts (user_id) values (me);
    return null;                                         -- wrong answer (no exception, so the attempt is kept)
  end if;
  delete from admin_attempts where user_id = me;
  insert into admin_unlocks (user_id, expires_at) values (me, v_exp)
  on conflict (user_id) do update set expires_at = excluded.expires_at;
  return v_exp;
end $$;

create function public.founder_lock() returns void
language sql security definer set search_path = public as $$
  delete from admin_unlocks where user_id = auth.uid()
$$;

create function public.founder_unlocked() returns boolean
language sql stable security definer set search_path = public as $$
  select is_platform_admin() and exists (select 1 from admin_unlocks where user_id = auth.uid() and expires_at > now())
$$;

create function public.founder_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if not founder_unlocked() then perform err('forbidden', 'Answer your security question first.'); end if;
  with
  clubs_x as (
    select c.id, c.name, c.is_published, c.created_at,
           club_core_filled(c.id) as core,
           (select count(*) from memberships m where m.club_id = c.id and m.status = 'active') as members,
           (select count(*) from memberships m where m.club_id = c.id and m.status = 'active' and m.recognition_ok) as supporters,
           (select count(*) from event_hosts h join events e on e.id = h.event_id where h.club_id = c.id and e.status <> 'cancelled' and e.starts_at < now()) as events_past,
           (select count(*) from event_hosts h join events e on e.id = h.event_id where h.club_id = c.id and e.status <> 'cancelled' and e.starts_at >= now()) as events_upcoming,
           (select count(*) from event_hosts h join attendance a on a.event_id = h.event_id where h.club_id = c.id and a.removed_at is null) as checkins,
           (select count(*) from event_hosts h join rsvps r on r.event_id = h.event_id where h.club_id = c.id) as rsvps,
           (select count(*) from event_hosts h join attendance a on a.event_id = h.event_id join rsvps r on r.event_id = a.event_id and r.user_id = a.user_id
             where h.club_id = c.id and a.removed_at is null) as showed,
           (select case when count(*) >= 3 then round(avg(x.stars), 1) end from event_hosts h join event_ratings x on x.event_id = h.event_id where h.club_id = c.id) as rating,
           greatest(c.created_at,
             (select max(m.created_at) from memberships m where m.club_id = c.id),
             (select max(a.recorded_at) from event_hosts h join attendance a on a.event_id = h.event_id where h.club_id = c.id)) as last_activity
      from clubs c
  ),
  people_x as (
    select p.id, p.name, p.email, p.major, p.class_year, p.created_at, p.onboarded_at, u.last_sign_in_at,
           (select count(*) from memberships m where m.user_id = p.id and m.status = 'active') as clubs,
           (select count(*) from memberships m where m.user_id = p.id and m.status = 'active' and m.role = 'officer') as officer_of,
           (select count(*) from attendance a where a.user_id = p.id and a.removed_at is null) as checkins,
           (select count(*) from rsvps r where r.user_id = p.id) as rsvps
      from profiles p left join auth.users u on u.id = p.id
  ),
  recent as (
    (select m.created_at as at, 'join' as kind, p.name || ' joined ' || c.name as text
       from memberships m join profiles p on p.id = m.user_id join clubs c on c.id = m.club_id order by m.created_at desc limit 25)
    union all
    (select c.created_at, 'club', 'New club: ' || c.name from clubs c order by c.created_at desc limit 10)
    union all
    (select e.created_at, 'event', 'Event posted: ' || e.title from events e order by e.created_at desc limit 15)
    union all
    (select a.recorded_at, 'checkin', a.attendee_name || ' checked in to ' || e.title
       from attendance a join events e on e.id = a.event_id where a.removed_at is null order by a.recorded_at desc limit 25)
  )
  select jsonb_build_object(
    'generated_at', now(),
    'totals', jsonb_build_object(
      'students', (select count(*) from profiles),
      'onboarded', (select count(*) from profiles where onboarded_at is not null),
      'active_7d', (select count(*) from people_x where last_sign_in_at > now() - interval '7 days'),
      'active_30d', (select count(*) from people_x where last_sign_in_at > now() - interval '30 days'),
      'new_7d', (select count(*) from profiles where created_at > now() - interval '7 days'),
      'clubs', (select count(*) from clubs),
      'clubs_published', (select count(*) from clubs where is_published),
      'clubs_forming', (select count(*) from clubs_x where not is_published and core < 4),
      'clubs_waiting_review', (select count(*) from clubs_x where not is_published and core = 4),
      'memberships', (select count(*) from memberships where status = 'active'),
      'events_past', (select count(*) from events where status <> 'cancelled' and starts_at < now()),
      'events_upcoming', (select count(*) from events where status <> 'cancelled' and starts_at >= now()),
      'checkins', (select count(*) from attendance where removed_at is null),
      'rsvps', (select count(*) from rsvps),
      'rsvps_that_came', (select count(*) from attendance a join rsvps r on r.event_id = a.event_id and r.user_id = a.user_id where a.removed_at is null),
      'ratings', (select count(*) from event_ratings),
      'rating_avg', (select case when count(*) >= 3 then round(avg(stars), 1) end from event_ratings),
      'notifications_7d', (select count(*) from notifications where created_at > now() - interval '7 days'),
      'open_reports', (select count(*) from reports where status = 'open')),
    'signups_by_day', (select jsonb_agg(jsonb_build_object('day', d::date, 'n',
                         (select count(*) from profiles p where p.created_at >= d and p.created_at < d + interval '1 day')) order by d)
                         from generate_series(date_trunc('day', now()) - interval '29 days', date_trunc('day', now()), interval '1 day') d),
    'checkins_by_week', (select jsonb_agg(jsonb_build_object('week', w::date, 'n',
                         (select count(*) from attendance a where a.removed_at is null and a.recorded_at >= w and a.recorded_at < w + interval '7 days')) order by w)
                         from generate_series(date_trunc('week', now()) - interval '11 weeks', date_trunc('week', now()), interval '1 week') w),
    'clubs', coalesce((select jsonb_agg(to_jsonb(c) order by c.last_activity desc nulls last) from clubs_x c), '[]'::jsonb),
    'people', coalesce((select jsonb_agg(to_jsonb(p) - 'id' order by p.last_sign_in_at desc nulls last, p.created_at desc)
                          from (select * from people_x order by last_sign_in_at desc nulls last limit 500) p), '[]'::jsonb),
    'recent', coalesce((select jsonb_agg(jsonb_build_object('at', at, 'kind', kind, 'text', text) order by at desc)
                          from (select at, kind, text from recent order by at desc limit 40) r), '[]'::jsonb)
  ) into v;
  return v;
end $$;

-- Grants: app users may ask for the question / try an answer / read the overview (each checks founder status itself).
revoke all on public.admin_secrets, public.admin_unlocks, public.admin_attempts from anon, authenticated;
revoke all on function public.set_admin_secret, public.admin_question, public.admin_unlock, public.founder_lock,
  public.founder_unlocked, public.founder_overview from anon, authenticated, public;
grant execute on function public.admin_question, public.admin_unlock, public.founder_lock, public.founder_unlocked,
  public.founder_overview to authenticated;
grant execute on function public.set_admin_secret to service_role;
