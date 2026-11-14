-- Archive (reversible, keeps history) or delete (permanent, only without check-in history) a club.
-- Who: the club's President, or the founder after the security-question unlock.

alter table public.clubs add column archived_at timestamptz;

-- Archived clubs disappear for everyone except their members (who keep read-only access to history).
create or replace function public.can_see_club(p_club uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from clubs c where c.id = p_club and (
           (c.is_published and c.archived_at is null and c.campus_id = my_campus())
        or exists (select 1 from memberships m where m.club_id = c.id and m.user_id = auth.uid())
        or exists (select 1 from club_invites i where i.club_id = c.id and i.status = 'pending' and i.email = my_email())
        or is_platform_admin()))
$$;

create or replace function public.can_see_event(p_event uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from events e join event_hosts h on h.event_id = e.id join clubs c on c.id = h.club_id
                  where e.id = p_event and e.campus_id = my_campus()
                    and ((c.is_published and c.archived_at is null) or is_club_member(c.id, auth.uid())))
$$;

create or replace function public.club_preview(p_club uuid) returns jsonb
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
    from clubs c where c.id = p_club and c.is_published and c.archived_at is null
$$;

create or replace function public.founder_overview() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v jsonb;
begin
  if not founder_unlocked() then perform err('forbidden', 'Answer your security question first.'); end if;
  with
  clubs_x as (
    select c.id, c.name, c.is_published, c.archived_at, c.created_at,
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
      'clubs_published', (select count(*) from clubs where is_published and archived_at is null),
      'clubs_archived', (select count(*) from clubs where archived_at is not null),
      'clubs_forming', (select count(*) from clubs_x where not is_published and archived_at is null and core < 4),
      'clubs_waiting_review', (select count(*) from clubs_x where not is_published and archived_at is null and core = 4),
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

create function public.can_manage_club(p_club uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select founder_unlocked() or exists (
    select 1 from memberships where club_id = p_club and user_id = auth.uid() and role = 'officer' and status = 'active'
       and lower(officer_title) = 'president')
$$;

create function public.archive_club(p_club uuid, p_archive boolean) returns void
language plpgsql security definer set search_path = public as $$
declare v_name text := (select name from clubs where id = p_club);
begin
  perform require_user();
  if v_name is null then perform err('not_found', 'That club no longer exists.'); end if;
  if not can_manage_club(p_club) then perform err('forbidden', 'Only the club''s president can do that.'); end if;
  if p_archive then
    update clubs set archived_at = coalesce(archived_at, now()) where id = p_club;
    -- upcoming events hosted only by this club are cancelled (records kept)
    update events set status = 'cancelled'
     where status <> 'cancelled' and starts_at > now()
       and id in (select event_id from event_hosts where club_id = p_club)
       and not exists (select 1 from event_hosts h where h.event_id = events.id and h.club_id <> p_club);
    update polls set closed_at = coalesce(closed_at, now()) where club_id = p_club;
    update club_invites set status = 'revoked', responded_at = now() where club_id = p_club and status = 'pending';
    perform notify_users(array(select user_id from memberships where club_id = p_club and status = 'active' and user_id <> auth.uid()),
      'announcement', p_club, null, v_name || ' is archived',
      'The club isn''t active anymore. Your check-in history is kept in your involvement record.', 'archived:' || p_club || ':' || now()::date);
  else
    update clubs set archived_at = null where id = p_club;
  end if;
end $$;

create function public.delete_club(p_club uuid, p_confirm_name text) returns void
language plpgsql security definer set search_path = public as $$
declare v_name text := (select name from clubs where id = p_club);
begin
  perform require_user();
  if v_name is null then perform err('not_found', 'That club no longer exists.'); end if;
  if not can_manage_club(p_club) then perform err('forbidden', 'Only the club''s president can do that.'); end if;
  if lower(btrim(coalesce(p_confirm_name, ''))) <> lower(v_name) then perform err('validation', 'Type the club''s name exactly to delete it.'); end if;
  if exists (select 1 from event_hosts h join attendance a on a.event_id = h.event_id where h.club_id = p_club and a.removed_at is null) then
    perform err('validation', 'People have checked in to this club''s events. Archive it instead so they keep their records.');
  end if;
  delete from events where id in (select event_id from event_hosts where club_id = p_club)
    and not exists (select 1 from event_hosts h where h.event_id = events.id and h.club_id <> p_club);
  delete from clubs where id = p_club;           -- memberships, invites, tasks, polls, notifications cascade
end $$;

-- Archived clubs are read-only: no new members, invites, events or polls.
create function public.archived_guard() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from clubs where id = new.club_id and archived_at is not null) then
    perform err('validation', 'This club is archived.');
  end if;
  return new;
end $$;
create trigger memberships_archived_guard before insert on public.memberships for each row execute function public.archived_guard();
create trigger invites_archived_guard before insert on public.club_invites for each row execute function public.archived_guard();
create trigger polls_archived_guard before insert on public.polls for each row execute function public.archived_guard();
create trigger event_hosts_archived_guard before insert on public.event_hosts for each row execute function public.archived_guard();

revoke all on function public.can_manage_club, public.archive_club, public.delete_club, public.archived_guard,
  public.can_see_club, public.can_see_event, public.club_preview, public.founder_overview from anon, authenticated, public;
grant execute on function public.archive_club, public.delete_club, public.can_see_club, public.can_see_event, public.founder_overview
  to authenticated;
grant execute on function public.club_preview to anon, authenticated;
