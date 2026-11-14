-- Profile photos (migration 20261118020000). Runs after v6_test.sql.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');   -- Ivy
select tests.fails($$select public.set_avatar('https://evil.example/x.jpg')$$, 'validation|');
select tests.fails($$select public.set_avatar('https://x.supabase.co/storage/v1/object/public/avatars/00000000-0000-0000-0000-0000000000f1/a.jpg')$$, 'validation|');   -- someone else's folder
select public.set_avatar('https://x.supabase.co/storage/v1/object/public/avatars/00000000-0000-0000-0000-0000000000a4/me.jpg');
select tests.as_user('00000000-0000-0000-0000-0000000000f1');   -- Finn sees Ivy's photo in People
do $$ begin assert (select avatar_url from public.people_to_meet() where name = 'Ivy M.') like '%/avatars/00000000-0000-0000-0000-0000000000a4/me.jpg'; end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');
select public.set_avatar(null);                                  -- remove
do $$ begin assert (select avatar_url is null from public.profiles where id = auth.uid()); end $$;
reset role;
set role anon;
select tests.fails($$select public.set_avatar(null)$$, 'permission denied');
reset role;
\echo 'ALL V7 TESTS PASSED'
