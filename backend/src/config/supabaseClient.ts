import { createClient } from '@supabase/supabase-js';
import { env } from './env';

/**
 * Server-side client using the service-role key — bypasses RLS.
 * Only ever used inside trusted backend code, never exposed to clients.
 */
export const supabaseAdmin = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});
