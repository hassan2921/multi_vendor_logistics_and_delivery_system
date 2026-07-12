import { config as loadDotenv } from 'dotenv';
import { z } from 'zod';

loadDotenv();

const notPlaceholder = (message: string) =>
  z
    .string()
    .min(1, message)
    .refine((value) => !value.startsWith('PLACEHOLDER'), {
      message: 'still set to the PLACEHOLDER value from .env.example — replace it with your real credential',
    });

const envSchema = z.object({
  PORT: z.coerce.number().default(3000),
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  SUPABASE_URL: notPlaceholder('SUPABASE_URL is required').refine(
    (value) => value.startsWith('http://') || value.startsWith('https://'),
    { message: 'must be a valid HTTP(S) URL, e.g. https://your-project.supabase.co' },
  ),
  SUPABASE_ANON_KEY: notPlaceholder('SUPABASE_ANON_KEY is required'),
  SUPABASE_SERVICE_ROLE_KEY: notPlaceholder('SUPABASE_SERVICE_ROLE_KEY is required'),
  STRIPE_SECRET_KEY: notPlaceholder('STRIPE_SECRET_KEY is required'),
  STRIPE_WEBHOOK_SECRET: notPlaceholder('STRIPE_WEBHOOK_SECRET is required'),

  // ── Pricing engine ────────────────────────────────────────────────
  DELIVERY_BASE_FEE_CENTS: z.coerce.number().int().nonnegative().default(199),
  DELIVERY_PER_KM_CENTS: z.coerce.number().int().nonnegative().default(60),
  DELIVERY_FEE_CAP_CENTS: z.coerce.number().int().nonnegative().default(999),

  // ── Marketplace economics ─────────────────────────────────────────
  // Platform commission taken from the item subtotal; the rest is the
  // vendor's share, transferred to their Stripe Connect account.
  PLATFORM_FEE_PERCENT: z.coerce.number().min(0).max(100).default(15),
  // Portion of the delivery fee credited to the courier (tips are always
  // passed through 100%).
  COURIER_DELIVERY_FEE_SHARE_PERCENT: z.coerce.number().min(0).max(100).default(80),

  // ── Stripe Connect onboarding redirect targets ────────────────────
  CONNECT_RETURN_URL: z.string().default('https://example.com/connect/return'),
  CONNECT_REFRESH_URL: z.string().default('https://example.com/connect/refresh'),

  // ── Firebase Cloud Messaging (optional — push is skipped if unset;
  //    in-app notifications still work via Supabase Realtime) ────────
  FCM_PROJECT_ID: z.string().optional(),
  FCM_CLIENT_EMAIL: z.string().optional(),
  FCM_PRIVATE_KEY: z.string().optional(),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  console.error('Invalid environment configuration:', parsed.error.flatten().fieldErrors);
  throw new Error('Missing or invalid environment variables. Copy backend/.env.example to backend/.env and fill it in.');
}

export const env = parsed.data;
