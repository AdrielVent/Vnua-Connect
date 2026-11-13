# Vnua-connect backend (Supabase)

All the rules live in the database (`migrations/`), so a modified app still can't break them:
- Clients can only **read**, and row-level security filters every read (campus isolation, private RSVPs, officers-only attendance).
- Every **write** is a Postgres function that re-checks who's calling: join, RSVP, pass, check-in, corrections, approvals, block, report, delete account.
- Sign-up is limited to campus email domains (`campuses.email_domains`) by a trigger on `auth.users`.

## Test locally (no Docker needed)
```
brew install postgresql@17
supabase/tests/run_local.sh        # → ALL SECURITY TESTS PASSED
```
`tests/security_test.sql` signs in as different students and officers to check that cross-campus, cross-club and self-promotion attempts all fail.

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
- **Email delivery (required for sign-in):** on the free plan, Supabase won't allow custom email templates while you use its built-in sender. Its default email only has a link, not the 6-digit code. Under Authentication → SMTP, connect a provider (Resend, Postmark, or Gmail with an app password for testing). Then uncomment the two `[auth.email.template.*]` blocks in `config.toml` and run `supabase config push --yes`.
- **Make yourself admin:** in the SQL editor, run `update profiles set is_platform_admin = true where email = '<your school email>';`. Admins can see unpublished clubs and reports.
- **Publish a club** after reviewing it: `update clubs set is_published = true where id = '<club id>';`. An in-app moderation screen comes later.
- **Pass cleanup** happens automatically: `issue_pass` deletes passes that expired over an hour ago.

## Adding another campus later
```sql
insert into campuses (id, name, email_domains) values ('adelphi', 'Adelphi University', array['adelphi.edu']);
```
Students with that domain land in their own campus automatically. Nothing is shared between campuses.

## Changing the schema
Never edit a migration that has already been pushed. Add a new file instead (`supabase migration new <name>`), add a test to `tests/security_test.sql`, run `run_local.sh`, then `supabase db push`.
