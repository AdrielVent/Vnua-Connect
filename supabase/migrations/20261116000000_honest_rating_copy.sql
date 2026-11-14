-- Honest wording for ratings. Ratings are stored with the rater's user id (so one person = one rating),
-- which means a database operator could identify a rater. Officers cannot: the table is unreadable to every
-- app user and officers only receive averages/totals from 3+ ratings. So the copy says exactly that and
-- no longer says "anonymous".

create or replace function public.send_due_notifications() returns int
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
             'Tap to give it 1–5 stars. Officers see averages, never names: your rating isn''t tied to you in anything they can access.', 'rate:' || r.id);
  end loop;

  delete from notifications where created_at < now() - interval '120 days';
  return n;
end $$;

-- Fix rating prompts already delivered with the old wording.
update public.notifications
   set body = 'Tap to give it 1–5 stars. Officers see averages, never names: your rating isn''t tied to you in anything they can access.'
 where kind = 'rating' and body like '%anonymous%';

revoke all on function public.send_due_notifications() from anon, authenticated, public;
