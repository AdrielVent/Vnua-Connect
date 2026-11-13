-- Officers create and cancel events from the app.

-- Create an event hosted by one or more clubs. The caller must be an officer of EVERY host club,
-- so nobody can attach another club's name to their event without that club's officers.
create function public.create_event(p_hosts uuid[], p_title text, p_starts_at timestamptz, p_duration int,
                                    p_location text, p_details text, p_request uuid)
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

  insert into events (campus_id, title, starts_at, duration_minutes, location, details, organizer, created_by)
  values (my_campus(), btrim(p_title), p_starts_at, coalesce(p_duration, 60), coalesce(btrim(p_location), ''),
          coalesce(btrim(p_details), ''), (select name from profiles where id = me), me)
  returning id into v_id;
  insert into event_hosts (event_id, club_id) select v_id, unnest(array(select distinct unnest(p_hosts)));
  perform idem_put(p_request, jsonb_build_object('id', v_id));
  return v_id;
exception when check_violation then
  perform err('validation', 'Check the event details (title length, duration 5 minutes to 24 hours).');
  return null;
end $$;

-- Cancel keeps the event (and its RSVPs/attendance) so members see what happened.
create function public.cancel_event(p_event uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_event_officer(p_event, require_user()) then perform err('forbidden', 'Only this club''s officers can do that.'); end if;
  update events set status = 'cancelled' where id = p_event;
end $$;

-- Supabase grants new functions to anon by default; signed-out users get nothing.
revoke all on function public.create_event, public.cancel_event from anon, public;
grant execute on function public.create_event, public.cancel_event to authenticated;
