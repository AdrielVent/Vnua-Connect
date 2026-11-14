-- Founder can publish / unpublish a club from the founder dashboard (instead of SQL). Requires the security-question unlock.
-- The publish guard trigger still refuses publishing until all four core officers have accepted.
create function public.founder_set_published(p_club uuid, p_published boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not founder_unlocked() then perform err('forbidden', 'Answer your security question first.'); end if;
  update clubs set is_published = p_published where id = p_club;
  if not found then perform err('not_found', 'That club no longer exists.'); end if;
  if p_published then
    perform notify_users(array(select user_id from memberships where club_id = p_club and role = 'officer' and status = 'active'),
      'approved', p_club, null, 'Your club is live', (select name from clubs where id = p_club) || ' now shows up in Discover for every student.',
      'published:' || p_club);
  end if;
end $$;
revoke all on function public.founder_set_published from anon, authenticated, public;
grant execute on function public.founder_set_published to authenticated;
