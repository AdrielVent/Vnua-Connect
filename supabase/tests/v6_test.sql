-- Open to connect + shared-major matching (migration 20261118000000). Runs after v5_test.sql.
\set ON_ERROR_STOP 1
set client_min_messages = warning;
set role authenticated;
-- Finn (CS, Games, findable) and Ivy (Biology, Games+Engineering, findable, LinkedIn set) exist from v2.
select tests.as_user('00000000-0000-0000-0000-0000000000a2');   -- Gia: same major as Finn, no shared interests, findable
select public.save_profile('Gia T.', 'cs', 'Senior', '', array['Music'], '', '', 'linkedin.com/in/gia', false, false, true, true);
select tests.as_user('00000000-0000-0000-0000-0000000000f1');   -- Finn
do $$ begin
  assert exists (select 1 from public.people_to_meet() where name = 'Gia T.' and same_major), 'same major (case-insensitive) matches without shared interests';
  assert (select linkedin from public.people_to_meet() where name = 'Ivy M.') = '', 'no LinkedIn unless both opted in';
end $$;
select tests.as_user('00000000-0000-0000-0000-0000000000a4');   -- Ivy opts in
select public.set_open_to_connect(true);
select tests.as_user('00000000-0000-0000-0000-0000000000f1');
do $$ begin assert (select linkedin from public.people_to_meet() where name = 'Ivy M.') = '', 'one-sided opt-in still hides LinkedIn'; end $$;
select public.set_open_to_connect(true);                         -- Finn opts in too
do $$ begin
  assert (select linkedin from public.people_to_meet() where name = 'Ivy M.') = 'https://linkedin.com/in/ivy', 'mutual opt-in shows LinkedIn';
  assert (select linkedin from public.people_to_meet() where name = 'Gia T.') = '', 'Gia never opted in';
end $$;
reset role;
set role anon;
select tests.fails($$select public.set_open_to_connect(true)$$, 'permission denied');
reset role;
set role authenticated;
select tests.as_user('00000000-0000-0000-0000-0000000000a5');   -- Jo: Undeclared, findable now
select public.save_profile('Jo N.', 'Undeclared', 'Senior', '', array['Sports'], '', '', '', false, false, true, true);
select tests.as_user('00000000-0000-0000-0000-0000000000a3');   -- Hal: Undeclared too, no shared interests with Jo
select public.save_profile('Hal S.', 'undeclared', 'Junior', '', array['Faith'], '', '', '', false, false, true, true);
do $$ begin assert not exists (select 1 from public.people_to_meet() where name = 'Jo N.'), '"Undeclared" is not a shared major'; end $$;
reset role;
\echo 'ALL V6 TESTS PASSED'
