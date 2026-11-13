-- Minimal stand-in for the parts of Supabase the migrations rely on, so they can run on plain Postgres
-- (no Docker needed). NOT applied to the real Supabase project.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;

create schema auth;
create table auth.users (
  id                 uuid primary key default gen_random_uuid(),
  email              text not null,
  raw_user_meta_data jsonb not null default '{}'
);

-- Supabase's auth.uid(): the "sub" claim of the caller's JWT.
create function auth.uid() returns uuid language sql stable as $$
  select nullif(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub', '')::uuid
$$;

grant usage on schema public, auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
-- Supabase's default: new tables/functions in public are granted to anon + authenticated.
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant execute on functions to anon, authenticated;
