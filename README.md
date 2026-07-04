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

## Repository layout

```
backend/     Node/Express API gateway (TypeScript)
lib/         Flutter app (customer, courier, vendor roles)
supabase/    SQL schema + RLS policies (shared source of truth)
```

## Setup

Everything runs against **your own free-tier accounts** — no paid services
required.

### 1. Supabase

1. Create a free project at [supabase.com](https://supabase.com).
2. Run [`supabase/migrations/0001_init.sql`](supabase/migrations/0001_init.sql)
   then [`supabase/policies.sql`](supabase/policies.sql) in the SQL editor.
3. Copy your Project URL, anon key, service role key, and JWT secret from
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

Run `npm test` to run the idempotency and Stripe-signature test suite (no
cloud credentials required — these run against local fakes).

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
2. As the vendor: no setup screen exists yet for creating a `vendors` row —
   insert one directly in the Supabase table editor with `owner_user_id` set
   to your vendor user's `id`, so it shows up in the customer's vendor list.
3. As the customer: pick the vendor, add a few line items, checkout, and pay
   with Stripe's test card `4242 4242 4242 4242`, any future expiry, any CVC.
4. The Stripe webhook marks the order `paid`; use the Supabase table editor
   (or a future vendor "accept" flow extension) to move it through
   `accepted → preparing → ready_for_pickup`.
5. As the courier: claim the job, start sharing location, and watch the
   customer's tracking screen update live. Use the Android emulator's
   Extended Controls > Location > Route playback to simulate movement
   without a real device.

## Known limitations (by design, for a portfolio-scoped build)

- Push notifications are Realtime-driven local notifications only — no true
  background push (documented trade-off from dropping Firebase/FCM).
- RLS policies are simplified, not production-hardened multi-tenant rules.
- No vendor onboarding UI yet (vendor rows are created directly in Supabase).
