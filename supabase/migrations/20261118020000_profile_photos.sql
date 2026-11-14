-- Optional profile photos ("like social media"), visible only to signed-in students on the same campus
-- (Profile, People, club e-board, officer member list). Never in the public shared-link preview.
-- Files live in the "avatars" storage bucket under <user id>/; only you can write your own folder.

alter table public.profiles add column avatar_url text check (avatar_url is null or char_length(avatar_url) <= 500);

create function public.set_avatar(p_url text) returns void
language plpgsql security definer set search_path = public as $$
declare me uuid := require_user();
begin
  if p_url is not null and p_url not like '%/storage/v1/object/public/avatars/' || me::text || '/%' then
    perform err('validation', 'Upload the photo through the app.');
  end if;
  update profiles set avatar_url = p_url where id = me;
end $$;

-- Officers on club pages get their photo.
drop view public.club_officers;
create view public.club_officers with (security_barrier) as
  select m.club_id, m.user_id, p.name, coalesce(m.officer_title, 'Officer') as title, coalesce(m.ask_about, '') as ask_about,
         p.email, case when p.share_phone then p.phone else '' end as phone,
         case when p.share_linkedin then p.linkedin else '' end as linkedin,
         p.major, p.class_year, p.pronouns, public.position_rank(m.officer_title) as rank, p.avatar_url
    from public.memberships m join public.profiles p on p.id = m.user_id
   where m.role = 'officer' and m.status = 'active' and public.can_see_club(m.club_id);
revoke all on public.club_officers from anon;
grant select on public.club_officers to authenticated;

drop function public.people_to_meet();
create function public.people_to_meet() returns table (user_id uuid, name text, major text, class_year text, pronouns text, bio text,
                                                       interests text[], shared text[], same_major boolean, email text, phone text,
                                                       linkedin text, common_clubs int, help_with text[], looking_for text[],
                                                       open_to_connect boolean, avatar_url text)
language sql stable security definer set search_path = public as $$
  select * from (
    select p.id, p.name, p.major, p.class_year, p.pronouns, p.bio, p.interests,
           array(select unnest(p.interests) intersect select unnest(me.interests)) as shared,
           (lower(btrim(p.major)) not in ('', 'undeclared', 'undecided', 'exploratory', 'none', 'n/a') and lower(btrim(p.major)) = lower(btrim(me.major))) as same_major,
           case when p.share_email then p.email else '' end as email,
           case when p.share_phone then p.phone else '' end as phone,
           -- mutual opt-in only
           case when p.open_to_connect and me.open_to_connect then p.linkedin else '' end as linkedin,
           (select count(*) from memberships a join memberships b on a.club_id = b.club_id
             where a.user_id = p.id and b.user_id = me.id and a.status = 'active' and b.status = 'active')::int as common,
           p.help_with, p.looking_for, p.open_to_connect, p.avatar_url
      from profiles p, profiles me
     where me.id = auth.uid() and me.discoverable and p.id <> me.id and p.campus_id = me.campus_id
       and p.discoverable and p.onboarded_at is not null
       and (p.interests && me.interests or (lower(btrim(p.major)) not in ('', 'undeclared', 'undecided', 'exploratory', 'none', 'n/a') and lower(btrim(p.major)) = lower(btrim(me.major))))
  ) t order by t.same_major desc, cardinality(t.shared) desc, t.common desc, t.name limit 60
$$;


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
    select m.user_id, p.name, p.email, p.avatar_url, p.major, p.class_year, p.help_with, m.role, m.officer_title, m.created_at as joined_at,
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
    'members', coalesce((select jsonb_agg(jsonb_build_object('user_id', user_id, 'name', name, 'email', email, 'avatar_url', avatar_url, 'major', major,
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

do $storage$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('avatars', 'avatars', true, 1048576, array['image/jpeg', 'image/png', 'image/webp'])
    on conflict (id) do nothing;
    execute $p$create policy avatars_insert on storage.objects for insert to authenticated with check (
      bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)$p$;
    execute $p$create policy avatars_update on storage.objects for update to authenticated using (
      bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)$p$;
    execute $p$create policy avatars_delete on storage.objects for delete to authenticated using (
      bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)$p$;
  end if;
end $storage$;

revoke all on function public.set_avatar, public.people_to_meet, public.club_insights from anon, authenticated, public;
grant execute on function public.set_avatar, public.people_to_meet, public.club_insights to authenticated;
