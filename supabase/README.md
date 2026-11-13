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

## Create the real project (one time)
1. Create a free project at supabase.com. Pick the US East region (closest to Hofstra) and save the database password.
2. Link and push the schema from the repo root:
   ```
   supabase login
   supabase link --project-ref <your-project-ref>
   supabase db push              # applies migrations/ (NOT seed.sql)
   supabase config push          # applies auth settings + the 6-digit code email template
   ```
   If `config push` isn't available on your plan, set them in the dashboard. Authentication → Emails → "Magic Link" and "Confirm signup" templates: body must contain `{{ .Token }}`. Authentication → Providers → Email: OTP expiry 600s.
3. App config: copy `VnuaConnect-iOS/Supabase.example.plist` to `VnuaConnect-iOS/VnuaConnect/Config/Supabase.plist`. Fill in the Project URL and the **anon / publishable** key from Project Settings → API. This file is git-ignored.
   Never put the `service_role` key in the app.
4. Run the app. With that file present it uses Supabase; without it, it runs the offline demo.

## Before real students use it
- **Email delivery:** Supabase's built-in email is rate-limited to a few messages per hour. Under Authentication → SMTP, connect a real provider (e.g. Resend or Postmark) using a domain you own.
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
