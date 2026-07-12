-- Adds the back-office admin role.
--
-- Kept in its own migration because ALTER TYPE ... ADD VALUE cannot run in
-- the same transaction as statements that use the new value (0004 does).
--
-- Admin accounts are never self-registered; promote a trusted user manually:
--   update users set role = 'admin' where email = 'ops@yourcompany.com';

alter type user_role add value if not exists 'admin';
