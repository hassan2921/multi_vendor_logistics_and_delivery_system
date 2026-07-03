-- Multi-vendor logistics and delivery system — initial schema.
-- Run this against your own Supabase project (SQL editor or `supabase db push`).

create extension if not exists pgcrypto;

create type user_role as enum ('customer', 'courier', 'vendor');

create type order_status as enum (
  'pending_payment',
  'paid',
  'accepted',
  'preparing',
  'ready_for_pickup',
  'courier_assigned',
  'picked_up',
  'in_transit',
  'delivered',
  'cancelled'
);

create table users (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid unique references auth.users(id) on delete cascade,
  email text unique not null,
  role user_role not null,
  full_name text,
  created_at timestamptz default now()
);

create table vendors (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references users(id),
  name text not null,
  address text,
  lat double precision,
  lng double precision,
  is_active boolean default true,
  created_at timestamptz default now()
);

create table orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references users(id) not null,
  vendor_id uuid references vendors(id) not null,
  courier_id uuid references users(id),
  status order_status not null default 'pending_payment',
  total_cents integer not null,
  currency text not null default 'usd',
  delivery_address text,
  delivery_lat double precision,
  delivery_lng double precision,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders(id) on delete cascade not null,
  name text not null,
  quantity integer not null check (quantity > 0),
  unit_price_cents integer not null check (unit_price_cents >= 0)
);

create table deliveries (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders(id) on delete cascade unique not null,
  courier_id uuid references users(id),
  status text not null default 'unassigned',
  assigned_at timestamptz,
  delivered_at timestamptz
);

create table location_pings (
  id bigint generated always as identity primary key,
  delivery_id uuid references deliveries(id) on delete cascade not null,
  courier_id uuid references users(id) not null,
  lat double precision not null,
  lng double precision not null,
  recorded_at timestamptz not null,
  received_at timestamptz default now()
);

create table payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references orders(id) on delete cascade unique not null,
  stripe_payment_intent_id text unique,
  status text not null default 'requires_payment_method',
  amount_cents integer not null,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- Backs the idempotency middleware (backend/src/middleware/idempotency.middleware.ts):
-- the unique constraint on `key` is what makes the INSERT act as a lock.
create table idempotency_keys (
  key text primary key,
  request_hash text not null,
  status text not null default 'processing',
  response_status int,
  response_body jsonb,
  created_at timestamptz default now()
);

-- Backs Stripe webhook de-duplication (backend/src/services/stripe.service.ts)
-- so Stripe's automatic delivery retries don't double-apply state changes.
create table stripe_events_seen (
  event_id text primary key,
  processed_at timestamptz default now()
);

create index orders_customer_id_idx on orders(customer_id);
create index orders_vendor_id_idx on orders(vendor_id);
create index orders_courier_id_idx on orders(courier_id);
create index orders_status_idx on orders(status);
create index location_pings_delivery_id_idx on location_pings(delivery_id);

-- Realtime is only needed on the tables clients live-subscribe to.
alter publication supabase_realtime add table orders;
alter publication supabase_realtime add table deliveries;
alter publication supabase_realtime add table location_pings;
