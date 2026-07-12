-- Industry feature pack: vendor payouts (Stripe Connect), auto-dispatch,
-- pricing engine (delivery fees / tips / promos), reviews, saved addresses,
-- notifications, and inventory tracking.
-- Run after 0003_admin_role.sql.

-- ── vendors: discovery, approval workflow, Stripe Connect ─────────────────

alter table vendors add column category text;
alter table vendors add column rating_avg numeric(3,2) not null default 0;
alter table vendors add column rating_count integer not null default 0;
alter table vendors add column approval_status text not null default 'pending'
  check (approval_status in ('pending', 'approved', 'rejected'));
alter table vendors add column stripe_account_id text;
alter table vendors add column payouts_enabled boolean not null default false;

-- Vendors that pre-date the approval workflow stay live.
update vendors set approval_status = 'approved';

-- ── orders: full pricing breakdown + ETA + scheduling ─────────────────────

alter table orders add column subtotal_cents integer;
alter table orders add column delivery_fee_cents integer not null default 0;
alter table orders add column tip_cents integer not null default 0;
alter table orders add column discount_cents integer not null default 0;
alter table orders add column promo_code text;
alter table orders add column eta_minutes integer;
alter table orders add column scheduled_for timestamptz;

-- Orders that pre-date fee breakdowns were pure item subtotals.
update orders set subtotal_cents = total_cents where subtotal_cents is null;

-- ── products: categories + inventory ──────────────────────────────────────

alter table products add column category text;
-- null = inventory not tracked for this product
alter table products add column stock_quantity integer check (stock_quantity >= 0);
alter table products add column image_url text;

-- ── couriers: availability + last known location (dispatch input) ─────────

alter table users add column is_available boolean not null default false;
alter table users add column last_lat double precision;
alter table users add column last_lng double precision;
alter table users add column last_seen_at timestamptz;

-- ── deliveries: courier earnings ledger + route stats ─────────────────────

alter table deliveries add column courier_payout_cents integer not null default 0;
alter table deliveries add column distance_km double precision;

-- ── payments: platform commission + Connect transfer tracking ─────────────

alter table payments add column application_fee_cents integer not null default 0;
alter table payments add column stripe_transfer_id text;

-- ── promo codes ────────────────────────────────────────────────────────────

create table promo_codes (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  description text,
  discount_type text not null check (discount_type in ('percent', 'fixed')),
  discount_value integer not null check (discount_value > 0),
  min_subtotal_cents integer not null default 0,
  max_discount_cents integer,
  valid_from timestamptz,
  valid_until timestamptz,
  max_redemptions integer,
  redemption_count integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz default now()
);

-- ── ratings & reviews ──────────────────────────────────────────────────────

create table reviews (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders(id) on delete cascade unique not null,
  vendor_id uuid references vendors(id) on delete cascade not null,
  customer_id uuid references users(id) not null,
  rating integer not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz default now()
);

create index reviews_vendor_id_idx on reviews(vendor_id);

-- ── saved delivery addresses ───────────────────────────────────────────────

create table addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade not null,
  label text not null,
  address_line text not null,
  lat double precision,
  lng double precision,
  is_default boolean not null default false,
  created_at timestamptz default now()
);

create index addresses_user_id_idx on addresses(user_id);

-- ── push notifications ─────────────────────────────────────────────────────

-- FCM device registrations (one row per installed app instance).
create table device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade not null,
  token text unique not null,
  platform text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index device_tokens_user_id_idx on device_tokens(user_id);

-- In-app notification inbox. Every notification lands here (streamed to the
-- app via Realtime) and is additionally mirrored to FCM when configured, so
-- notifications work even before Firebase credentials are set up.
create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references users(id) on delete cascade not null,
  title text not null,
  body text not null,
  data jsonb,
  read boolean not null default false,
  created_at timestamptz default now()
);

create index notifications_user_id_idx on notifications(user_id, created_at desc);

alter publication supabase_realtime add table notifications;

-- ── atomic inventory adjustment ────────────────────────────────────────────

-- Single-statement conditional update = safe under concurrent checkouts.
-- No row updated (null result) means either the product is untracked or
-- stock was insufficient — callers must distinguish before calling.
create or replace function adjust_stock(p_product_id uuid, p_delta integer)
returns boolean
language sql
as $$
  update products
  set stock_quantity = stock_quantity + p_delta
  where id = p_product_id
    and stock_quantity is not null
    and stock_quantity + p_delta >= 0
  returning true;
$$;

-- ── row-level security ─────────────────────────────────────────────────────

-- promo_codes / device_tokens: backend-only (service role bypasses RLS);
-- enabling RLS with no policies blocks all direct client access.
alter table promo_codes enable row level security;
alter table device_tokens enable row level security;

-- reviews: public to read (social proof on storefronts); writes go through
-- the backend so it can enforce "one review per delivered order you placed".
alter table reviews enable row level security;

create policy "reviews_select_all" on reviews
  for select using (true);

-- addresses: a user reads only their own address book (writes via backend).
alter table addresses enable row level security;

create policy "addresses_select_own" on addresses
  for select using (
    user_id in (select id from users where auth_user_id = auth.uid())
  );

-- notifications: a user sees their own inbox and can mark entries read.
alter table notifications enable row level security;

create policy "notifications_select_own" on notifications
  for select using (
    user_id in (select id from users where auth_user_id = auth.uid())
  );

create policy "notifications_update_own" on notifications
  for update using (
    user_id in (select id from users where auth_user_id = auth.uid())
  );
