// Fake-but-well-formed env values so config/env.ts's zod validation passes
// during tests. No real Supabase/Stripe project is contacted — the
// supabase client is mocked (see tests/fakeSupabase.ts) and Stripe's
// signature-verification tests only exercise the pure crypto/SDK logic.
process.env.SUPABASE_URL = 'https://fake-project.supabase.co';
process.env.SUPABASE_ANON_KEY = 'fake-anon-key';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'fake-service-role-key';
process.env.SUPABASE_JWT_SECRET = 'fake-jwt-secret';
process.env.STRIPE_SECRET_KEY = 'sk_test_fake';
process.env.STRIPE_WEBHOOK_SECRET = 'whsec_test_fake_secret';
