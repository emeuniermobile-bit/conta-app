-- Reproduit le strict minimum de l'environnement Supabase pour tester les
-- migrations sur un Postgres nu (scripts/test-db.sh).
create schema if not exists extensions;
create schema if not exists auth;
do $$ begin
  create role anon nologin;
  create role authenticated nologin;
  create role service_role nologin;
exception when duplicate_object then null; end $$;
create table if not exists auth.users (id uuid primary key default gen_random_uuid(), phone text unique);
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth, public, extensions to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
-- Droits par défaut de Supabase : tout est ouvert, RLS fait le tri.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to anon, authenticated, service_role;
