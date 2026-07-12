# Multi-Vendor Logistics & Delivery System

A full-stack, real-time delivery platform: a role-based Flutter app (customer,
courier, vendor), a Node/Express API gateway, and Supabase (Postgres +
Realtime + Auth) for data and live sync. Stripe (test mode) handles payments.

## Highlighted engineering

1. **Throttled/batched courier GPS sync** — [`lib/features/courier/location_service.dart`](lib/features/courier/location_service.dart)
   filters GPS updates at the device level (`distanceFilter`) and batches them
   app-side (flush every 10s or every 5 points, whichever first) into a single
   Supabase insert, bounding write volume regardless of GPS chattiness.
2. **Secure Stripe webhook & payment gateway** — [`backend/src/services/stripe.service.ts`](backend/src/services/stripe.service.ts)
   creates PaymentIntents server-side (the client only ever sees a
   `client_secret`) and verifies webhook signatures against the raw request
   body ([`backend/src/app.ts`](backend/src/app.ts) mounts the webhook route
   ahead of the JSON body parser for this reason).
3. **Idempotent order/payment creation** — [`backend/src/middleware/idempotency.middleware.ts`](backend/src/middleware/idempotency.middleware.ts)
   uses a Postgres unique-constraint insert as a lock keyed by an
   `Idempotency-Key` header, replaying the cached response for a repeated key
   instead of creating a duplicate order.
4. **Server-side pricing from the product catalog** — [`backend/src/services/orders.service.ts`](backend/src/services/orders.service.ts)
   prices every order from the vendor's `products` table by id; the client only
   ever sends `{productId, quantity}`, so a tampered client can't discount its
   own order. Also validates the product belongs to the selected vendor and is
   currently available.
5. **Cancellation with automatic refund** — [`backend/src/services/orders.service.ts`](backend/src/services/orders.service.ts)
   enforces who can cancel (the owning customer or vendor) and which statuses
   are still cancellable; the controller then calls
   [`stripeService.refundIfPaid`](backend/src/services/stripe.service.ts), which
   is a no-op unless the order actually had a captured payment.
6. **Server-side pricing engine with a binding quote** — [`backend/src/services/pricing.service.ts`](backend/src/services/pricing.service.ts)
   computes distance-based delivery fees (haversine, capped), ETA, tips, and
   promo-code discounts; `POST /orders/quote` and order creation share one
   code path, so the checkout preview always equals the charged total. Promo
   redemptions are only counted when an order is actually placed.
7. **Marketplace payouts via Stripe Connect** — [`backend/src/services/payouts.service.ts`](backend/src/services/payouts.service.ts)
   onboards vendors onto Stripe Express accounts and, on delivery, transfers
   the vendor's share (subtotal minus platform commission) to their account —
   idempotently, so a retried webhook can't double-pay. Courier earnings
   (delivery-fee share + 100% of tips) are recorded per delivery.
8. **Auto-dispatch of the nearest courier** — [`backend/src/services/dispatch.service.ts`](backend/src/services/dispatch.service.ts)
   ranks available couriers by distance to the pickup point (ignoring stale
   locations and couriers mid-delivery) when an order becomes
   `ready_for_pickup`; it reuses the same race-safe conditional-update claim
   as manual self-claim, so the two modes can coexist.
9. **Two-tier notifications** — [`backend/src/services/notifications.service.ts`](backend/src/services/notifications.service.ts)
   writes every order event to a `notifications` inbox table (streamed to the
   app over Supabase Realtime with zero external config) and additionally
   pushes via FCM's HTTP v1 API — hand-rolled OAuth2 JWT grant, no Firebase
   SDK dependency — when service-account credentials are configured.
10. **Race-safe inventory** — migration [`0004`](supabase/migrations/0004_industry_features.sql)
    adds an `adjust_stock` SQL function (single conditional `UPDATE`) so two
    concurrent checkouts can't oversell the last unit; stock returns to the
    shelf on cancellation.

## Repository layout

```
backend/     Node/Express API gateway (TypeScript)
lib/         Flutter app (customer, courier, vendor roles)
supabase/    SQL schema + RLS policies (shared source of truth)
```

## Quick Start (Local Development)

Run the entire stack locally in 3 terminals:

```bash
# Terminal 1: Start Supabase (database & auth)
npx supabase start

# Terminal 2: Start Backend API
cd backend
npm install && npm run dev

# Terminal 3: Start Flutter app
flutter pub get && flutter run
```

Then create test accounts via the Register screen:
- **Customer**: customer@test.com / password123
- **Vendor**: vendor@test.com / password123
- **Courier**: courier@test.com / password123

Test Stripe payment: `4242 4242 4242 4242`, any future expiry, any CVC.

---

## Full Setup (Production/Remote Supabase)

Everything runs against **your own free-tier accounts** — no paid services
required.

### 1. Supabase

1. Create a free project at [supabase.com](https://supabase.com).
2. Run, in order, [`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql),
   [`supabase/migrations/0002_products_and_refunds.sql`](supabase/migrations/0002_products_and_refunds.sql),
   [`supabase/migrations/0003_admin_role.sql`](supabase/migrations/0003_admin_role.sql),
   [`supabase/migrations/0004_industry_features.sql`](supabase/migrations/0004_industry_features.sql),
   [`supabase/migrations/0005_grants.sql`](supabase/migrations/0005_grants.sql),
   [`supabase/migrations/0006_vendor_image.sql`](supabase/migrations/0006_vendor_image.sql),
   then [`supabase/policies.sql`](supabase/policies.sql) in the SQL editor.
3. Copy your Project URL, anon key, and service role key from
   *Project Settings > API*.

### 2. Stripe

1. Create a free account at [stripe.com](https://stripe.com) — test mode
   works immediately, no business verification needed.
2. Grab your test publishable/secret keys from
   *Developers > API keys*.
3. Install the [Stripe CLI](https://stripe.com/docs/stripe-cli) and run
   `stripe listen --forward-to localhost:3000/payments/webhook` to get a
   webhook signing secret for local dev.

### 3. Backend

```bash
cd backend
cp .env.example .env   # fill in Supabase + Stripe values from above
npm install
npm run dev             # http://localhost:3000
```

Run `npm test` to run the test suite — idempotency, Stripe webhooks, orders,
pricing/promos, dispatch, reviews, and inventory (no cloud credentials
required — these run against local fakes).

Optional env (see [`.env.example`](backend/.env.example)): delivery-fee and
commission rates, Stripe Connect redirect URLs, and FCM service-account
credentials for real push notifications.

#### Demo data

`npm run seed:demo` fills the Supabase project with a realistic demo dataset:
8 approved vendors with 72 menu items (each with a real Unsplash photo for
the storefront cover and every product), a month of order history (39 orders
covering every lifecycle state, including a live in-transit order with GPS
tracking pings), reviews with rolled-up vendor ratings, promo codes
(`WELCOME10`, `SAVE5`, `SUMMER25`), saved addresses, and notification inboxes.

It is safe to re-run: everything it creates hangs off `@demo.com` accounts,
and it wipes that slice (and only that slice) before reseeding.

Demo logins (password for all: `DemoPass123!`):

| Role     | Email               | Notes                          |
| -------- | ------------------- | ------------------------------ |
| Customer | `customer@demo.com` | order history, saved addresses |
| Vendor   | `vendor@demo.com`   | owns Bella Napoli Pizzeria     |
| Courier  | `courier@demo.com`  | has an active in-transit job   |
| Admin    | `admin@demo.com`    | full platform view             |

### 4. Flutter app

```bash
cp .env.example .env   # fill in SUPABASE_URL/ANON_KEY, Stripe publishable key,
                        # API_BASE_URL, and (optionally) a Google Maps API key
flutter pub get
flutter run
```

A Google Maps API key is only needed to render map tiles on the tracking
screen — the rest of the app runs without one. Add it to `.env` and also to
`android/app/src/main/AndroidManifest.xml` / `ios/Runner/AppDelegate.swift`
(both currently contain a `PLACEHOLDER_GOOGLE_MAPS_API_KEY`).

`flutter analyze` and `flutter test` run without any of the above — the
courier throttling logic is unit-tested with a fake position stream.

### Manual end-to-end walkthrough

1. Register a vendor account, then a courier account, then a customer
   account (role picker is on the register screen).
2. As the vendor: you'll land on a storefront setup screen first time in —
   fill in a name and (optionally) an address, then use the menu icon in the
   app bar to add a few menu items with prices.
3. As the customer: pick the vendor, adjust quantities on their menu items,
   enter a delivery address, checkout, and pay with Stripe's test card
   `4242 4242 4242 4242`, any future expiry, any CVC.
4. The Stripe webhook marks the order `paid`; as the vendor, tap into the
   order from *Incoming orders* and advance it through
   `accepted → preparing → ready_for_pickup`.
5. As the courier: claim the job, start sharing location, and watch the
   customer's tracking screen update live. Use the Android emulator's
   Extended Controls > Location > Route playback to simulate movement
   without a real device.
6. Try cancellation: as the customer, open *My orders* (receipt icon on the
   vendor list screen) and cancel an order that's still `paid`/`accepted`/
   `preparing` — if it was already paid, the backend issues a real Stripe
   test-mode refund automatically.

### Beyond the basics

- **Customer**: vendor search + category filters + rating sort, saved
  addresses (address book drives distance-based fees/ETA at checkout), tips,
  promo codes, a live checkout quote, post-delivery ratings & reviews, and a
  realtime notification inbox (bell icon).
- **Courier**: an availability toggle that opts into auto-dispatch (nearest
  courier wins) and an earnings screen (delivery-fee share + tips per job).
- **Vendor**: product categories, optional stock tracking with oversell
  protection and one-tap restock, and a Stripe Connect payouts screen.
- **Admin**: promote a user with
  `update users set role = 'admin' where email = '...'` — they get a console
  with platform metrics (GMV, fees, courier liquidity), a vendor approval
  queue (new vendors start `pending` and are hidden until approved), a
  platform-wide order feed, and promo-code management.

## Known limitations (by design, for a portfolio-scoped build)

- True background push requires configuring FCM service-account credentials
  on the backend (see `.env.example`); without them, notifications are
  in-app only (Supabase Realtime inbox).
- RLS policies are simplified, not production-hardened multi-tenant rules.
- Courier payouts are recorded as an earnings ledger, not yet transferred to
  courier bank accounts (vendors do get real Stripe Connect transfers).
