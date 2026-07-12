-- Grant table privileges to the Supabase API roles.
--
-- Newer Supabase (CLI/local dev) no longer auto-grants privileges on
-- newly created tables to anon/authenticated/service_role (see the
-- `auto_expose_new_tables` note in supabase/config.toml). Access is still
-- gated by the RLS policies in supabase/policies.sql; these grants only
-- make the tables visible to those policies in the first place.
grant usage on schema public to anon, authenticated, service_role;

grant select, insert, update, delete on all tables in schema public
  to anon, authenticated, service_role;

grant usage, select on all sequences in schema public
  to anon, authenticated, service_role;

alter default privileges in schema public
  grant select, insert, update, delete on tables to anon, authenticated, service_role;

alter default privileges in schema public
  grant usage, select on sequences to anon, authenticated, service_role;
