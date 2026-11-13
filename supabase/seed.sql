-- Demo data for LOCAL development only (`supabase db reset`). Never pushed to the hosted project.
insert into public.clubs (id, campus_id, monogram, accent_hex, name, interest, blurb, about, recognition, funded, requires_approval, is_published) values
  ('10000000-0000-0000-0000-000000000001', 'hofstra', 'LD', '#1f5a6b', 'Lowlight Drama Collective', 'Performing arts',
   'Readings, rehearsals and small shows. All experience levels.',
   'A student-led group that stages readings and short productions. No auditions to join; roles are opt-in per show.',
   'not_recognized', false, false, true),
  ('10000000-0000-0000-0000-000000000002', 'hofstra', 'OA', '#2c455d', 'Orbit & Airframe Society', 'Engineering',
   'Build nights for rockets, gliders and anyone flight-curious.', 'Hands-on aerospace builds and talks. Open to any major.',
   'recognized', false, false, true),
  ('10000000-0000-0000-0000-000000000003', 'hofstra', 'HP', '#7a4f12', 'Harbor Street Pottery Circle', 'Creative',
   'Wheel and hand-building sessions. Beginners welcome.', 'Casual weekly sessions at a shared studio.',
   'not_stated', null, true, true);

insert into public.events (id, campus_id, title, starts_at, duration_minutes, location, details, organizer) values
  ('20000000-0000-0000-0000-000000000001', 'hofstra', 'Open read-through: Act One', date_trunc('day', now()) + interval '1 day 18 hours 30 minutes', 90,
   'Studio 2 (demo room)', 'Read aloud together. No preparation needed.', 'Ava R.'),
  ('20000000-0000-0000-0000-000000000002', 'hofstra', 'Paper-rocket build night', date_trunc('day', now()) + interval '3 days 19 hours', 120,
   'Maker room (demo)', 'Build and launch small paper rockets.', 'Dev S.');
insert into public.event_hosts values
  ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001'),
  ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000002');
