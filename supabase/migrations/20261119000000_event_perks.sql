-- Event perks: what an event offers, so it catches attention on event cards and shared links.
-- Fixed list (no free text) so it stays honest and consistent: food, swag, resources, prizes, networking, beginners.

alter table public.events add column perks text[] not null default '{}'
  check (perks <@ array['food', 'swag', 'resources', 'prizes', 'networking', 'beginners']);

create function public.clean_perks(p text[]) returns text[]
language sql immutable as $$
  select coalesce(array(select distinct x from unnest(coalesce(p, '{}')) x
                         where x in ('food', 'swag', 'resources', 'prizes', 'networking', 'beginners') order by 1), '{}')
$$;

drop function public.create_event(uuid[], text, timestamptz, int, text, text, uuid, int[], jsonb);
create function public.create_event(p_hosts uuid[], p_title text, p_starts_at timestamptz, p_duration int,
                                    p_location text, p_details text, p_request uuid, p_reminders int[] default '{1440,120}',
                                    p_newcomer jsonb default '{}', p_perks text[] default '{}')
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

  insert into events (campus_id, title, starts_at, duration_minutes, location, details, organizer, created_by, reminders, newcomer, perks)
  values (my_campus(), btrim(p_title), p_starts_at, coalesce(p_duration, 60), coalesce(btrim(p_location), ''),
          coalesce(btrim(p_details), ''), (select name from profiles where id = me), me,
          array(select distinct unnest(coalesce(p_reminders, '{}')) order by 1 desc), clean_newcomer(p_newcomer),
          clean_perks(p_perks))
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

drop function public.update_event(uuid, text, timestamptz, int, text, text, int[], jsonb);
create function public.update_event(p_event uuid, p_title text, p_starts_at timestamptz, p_duration int, p_location text,
                                    p_details text, p_reminders int[], p_newcomer jsonb,
                                    p_perks text[] default '{}') returns void
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
         reminders = array(select distinct unnest(coalesce(p_reminders, '{}')) order by 1 desc), newcomer = clean_newcomer(p_newcomer), perks = clean_perks(p_perks),
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

create or replace function public.event_preview(p_event uuid) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('id', e.id, 'title', e.title, 'starts_at', e.starts_at, 'duration_minutes', e.duration_minutes,
           'location', e.location, 'details', e.details, 'status', e.status, 'newcomer', e.newcomer, 'perks', e.perks,
           'hosts', (select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name)) from event_hosts h join clubs c on c.id = h.club_id
                      where h.event_id = e.id and c.is_published))
    from events e
   where e.id = p_event
     and exists (select 1 from event_hosts h join clubs c on c.id = h.club_id where h.event_id = e.id and c.is_published)
$$;

revoke all on function public.create_event, public.update_event, public.event_preview, public.clean_perks from anon, authenticated, public;
grant execute on function public.create_event, public.update_event to authenticated;
grant execute on function public.event_preview to anon, authenticated;
