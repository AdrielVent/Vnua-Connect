-- "Undeclared" (and similar) is not a shared major: don't match or label everyone who hasn't picked one.

drop function public.people_to_meet();
create function public.people_to_meet() returns table (user_id uuid, name text, major text, class_year text, pronouns text, bio text,
                                                       interests text[], shared text[], same_major boolean, email text, phone text,
                                                       linkedin text, common_clubs int, help_with text[], looking_for text[],
                                                       open_to_connect boolean)
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
           p.help_with, p.looking_for, p.open_to_connect
      from profiles p, profiles me
     where me.id = auth.uid() and me.discoverable and p.id <> me.id and p.campus_id = me.campus_id
       and p.discoverable and p.onboarded_at is not null
       and (p.interests && me.interests or (lower(btrim(p.major)) not in ('', 'undeclared', 'undecided', 'exploratory', 'none', 'n/a') and lower(btrim(p.major)) = lower(btrim(me.major))))
  ) t order by t.same_major desc, cardinality(t.shared) desc, t.common desc, t.name limit 60
$$;

revoke all on function public.people_to_meet from anon, authenticated, public;
grant execute on function public.people_to_meet to authenticated;
