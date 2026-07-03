-- Row-Level Security policies.
--
-- NOTE: these are simplified for a portfolio project, not hardened for
-- production multi-tenant use (e.g. no rate limiting, no audit trail, no
-- policy on idempotency_keys/stripe_events_seen — those are only ever
-- touched by the backend's service-role key, which bypasses RLS entirely).

alter table users enable row level security;
alter table vendors enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table deliveries enable row level security;
alter table location_pings enable row level security;
alter table payments enable row level security;

-- users: a user can read/update their own row.
create policy "users_select_own" on users
  for select using (auth.uid() = auth_user_id);

create policy "users_update_own" on users
  for update using (auth.uid() = auth_user_id);

-- vendors: publicly readable (customers need to browse vendors); only the
-- owning vendor user can update their own vendor row.
create policy "vendors_select_all" on vendors
  for select using (true);

create policy "vendors_update_own" on vendors
  for update using (
    owner_user_id in (select id from users where auth_user_id = auth.uid())
  );

-- orders: customer sees their own orders; vendor sees orders placed at
-- their vendor; courier sees orders assigned to them, plus unclaimed jobs
-- ready for pickup.
create policy "orders_select_customer" on orders
  for select using (
    customer_id in (select id from users where auth_user_id = auth.uid())
  );

create policy "orders_select_vendor" on orders
  for select using (
    vendor_id in (
      select v.id from vendors v
      join users u on u.id = v.owner_user_id
      where u.auth_user_id = auth.uid()
    )
  );

create policy "orders_select_courier" on orders
  for select using (
    courier_id in (select id from users where auth_user_id = auth.uid())
    or (status = 'ready_for_pickup' and courier_id is null)
  );

-- order_items: readable by anyone who can read the parent order.
create policy "order_items_select" on order_items
  for select using (
    order_id in (select id from orders)
  );

-- deliveries / location_pings: courier can insert their own pings; anyone
-- tied to the order (customer, vendor, assigned courier) can read them.
create policy "deliveries_select" on deliveries
  for select using (
    order_id in (select id from orders)
  );

create policy "location_pings_insert_own" on location_pings
  for insert with check (
    courier_id in (select id from users where auth_user_id = auth.uid())
  );

create policy "location_pings_select" on location_pings
  for select using (
    delivery_id in (select id from deliveries)
  );

-- payments: customer can read their own order's payment status.
create policy "payments_select_customer" on payments
  for select using (
    order_id in (
      select id from orders where customer_id in (
        select id from users where auth_user_id = auth.uid()
      )
    )
  );
