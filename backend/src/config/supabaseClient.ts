import { createClient } from '@supabase/supabase-js';
import WebSocket from 'ws';
import { env } from './env';

/**
 * Server-side client using the service-role key — bypasses RLS.
 * Only ever used inside trusted backend code, never exposed to clients.
 * `ws` is injected as the realtime transport since Node 20 has no native
 * WebSocket global (Node 22+ does); supabase-js throws at construction
 * time without one.
 */
export const supabaseAdmin = createClient(env.SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
  realtime: {
    // ws and supabase-js disagree on event-handler types; runtime-compatible.
    transport: WebSocket as unknown as NonNullable<
      NonNullable<Parameters<typeof createClient>[2]>['realtime']
    >['transport'],
  },
});
