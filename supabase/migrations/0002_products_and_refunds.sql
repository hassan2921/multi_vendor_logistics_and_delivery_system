-- Product catalog + refund support.
-- Run after 0001_init.sql.

create table products (
  id uuid primary key default gen_random_uuid(),
  vendor_id uuid references vendors(id) on delete cascade not null,
  name text not null,
  description text,
  price_cents integer not null check (price_cents >= 0),
  is_available boolean not null default true,
  created_at timestamptz default now()
);

create index products_vendor_id_idx on products(vendor_id);

-- One storefront per owning vendor user; the onboarding endpoint relies on
-- this to make "create my vendor" idempotent.
alter table vendors add constraint vendors_owner_user_id_key unique (owner_user_id);

-- Line items snapshot name/price at purchase time (so later menu edits don't
-- rewrite past orders) but keep a reference to the product they came from.
alter table order_items add column product_id uuid references products(id);

alter table payments add column stripe_refund_id text;

alter table products enable row level security;

-- Customers browse menus directly from Supabase; writes go through the
-- Express backend (service role), so no client write policies are needed.
create policy "products_select_all" on products
  for select using (true);
