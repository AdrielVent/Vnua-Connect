# Vnua-connect backend (Supabase)

All the rules live in the database (`migrations/`), so a modified app still can't break them:
- Clients can only **read**, and row-level security filters every read (campus isolation, private RSVPs, officers-only attendance).
- Every **write** is a Postgres function that re-checks who's calling: join, RSVP, pass, check-in, corrections, approvals, block, report, delete account.
- Sign-up is limited to campus email domains (`campuses.email_domains`) by a trigger on `auth.users`.
- Signed-in users can only call a **whitelist** of functions (see the grants at the end of each migration). Server-only helpers such as `notify_users` and `send_due_notifications` can't be called from the app.

## What the database does (migration `20261114000000`)
- **Profiles + onboarding:** major, year, pronouns, up to 3 interests, optional phone/LinkedIn with per-field sharing switches. `onboarded_at` is set by `save_profile`.
- **Officer teams:** `create_club` makes the creator an officer (President by default). `invite_officer` invites by school email; `respond_invite` accepts. A trigger refuses `is_published = true` until President, Vice President, Treasurer and Secretary are all held. Extra positions are allowed.
- **Club logos:** public `club-logos` storage bucket; only a club's officers can write under `<club id>/`.
- **Notifications (in-app inbox):** new events, cancellations, approvals, officer invites, announcements, "still interested?" nudges. Each member picks *Everything / Just what I RSVP to / Nothing* per club.
- **Scheduled reminders:** `pg_cron` runs `send_due_notifications()` every 5 minutes. It sends each event's chosen reminders (2 weeks … 30 minutes before) and, 15 minutes after an event ends, asks everyone who checked in for a rating.
- **Anonymous ratings:** `event_ratings` can't be read by any client. Officers get an average only once 3+ people rated.
- **Officer data:** `event_stats` (RSVPs, check-ins, how many RSVPs came, ratings) and `club_insights` (every member ranked by check-ins, officers flagged so they're left out of rankings and "top supporters", members who missed the last 3 events).
- **Members:** `club_leaderboard` (members only, officers not ranked, opt-out in Profile) and `people_to_meet` (shared interests; you only see others while you're findable too).

## Test locally (no Docker needed)
```
brew install postgresql@17
supabase/tests/run_local.sh        # → ALL SECURITY TESTS PASSED, ALL V2 TESTS PASSED
```
`tests/security_test.sql` signs in as different students and officers to check that cross-campus, cross-club and self-promotion attempts all fail. `tests/v2_test.sql` covers officer teams, invites, reminders, anonymous ratings, nudges, leaderboards and the function whitelist. (pg_cron and Storage don't exist in plain Postgres, so those parts are skipped locally.)

## Hosted project (done)
- Project: `vnua-connect` (ref `mjxriwbyvfyndrwtqeeh`, us-east-1), linked to this repo.
- Database password: macOS Keychain → "Supabase DB password (vnua-connect)".
- Schema pushed with `supabase db push --remote`. Auth settings (6-digit codes, 10-minute expiry) pushed with `supabase config push --yes`.
- The app reads `VnuaConnect-iOS/VnuaConnect/Config/Supabase.plist` (git-ignored, anon key only).

To push a new migration later:
```
PW=$(security find-generic-password -a vnua-connect -s "Supabase DB password (vnua-connect)" -w)
supabase db push --remote --dry-run -p "$PW"     # review
supabase db push --remote --yes -p "$PW"
```
Run `supabase config diff` before every `config push`. The local file must match production apart from the settings you mean to change.

## Before real students use it
- **Email delivery (required for code sign-in):** on the free plan, Supabase won't allow custom email templates while you use its built-in sender, and its default email only has a link, not the 6-digit code. Under Authentication → Emails → SMTP, connect a provider (Gmail with an app password works for free; Resend with your own domain for real use). Then paste `templates/code.html` into the "Magic link" and "Confirm signup" templates in the dashboard. Don't `config push` templates without mirroring the SMTP settings first (see the warning in `config.toml`).
- **Make yourself admin:** in the SQL editor, run `update profiles set is_platform_admin = true where email = '<your school email>';`. Admins can see unpublished clubs and reports.
- **Publish a club** after reviewing it: `update clubs set is_published = true where id = '<club id>';`. It only works once all four core officers have accepted. An in-app moderation screen comes later.
- **Pass cleanup** happens automatically: `issue_pass` deletes passes that expired over an hour ago.

## Adding another campus later
```sql
insert into campuses (id, name, email_domains) values ('adelphi', 'Adelphi University', array['adelphi.edu']);
```
Students with that domain land in their own campus automatically. Nothing is shared between campuses.

## Changing the schema
Never edit a migration that has already been pushed. Add a new file instead (`supabase migration new <name>`), add a test to `tests/security_test.sql`, run `run_local.sh`, then `supabase db push`.
