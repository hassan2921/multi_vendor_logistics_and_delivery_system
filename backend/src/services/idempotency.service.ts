import { createHash } from 'crypto';
import { supabaseAdmin } from '../config/supabaseClient';

export type IdempotencyRecord = {
  key: string;
  request_hash: string;
  status: 'processing' | 'completed';
  response_status: number | null;
  response_body: unknown;
};

export function hashRequest(method: string, path: string, body: unknown): string {
  const normalized = JSON.stringify(body ?? {}, Object.keys(body ?? {}).sort());
  return createHash('sha256').update(`${method}:${path}:${normalized}`).digest('hex');
}

/**
 * Attempts to claim an idempotency key. The unique-constraint insert acts as
 * the lock: exactly one caller wins the INSERT for a given key.
 */
export async function claimIdempotencyKey(
  key: string,
  requestHash: string
): Promise<{ claimed: true } | { claimed: false; existing: IdempotencyRecord }> {
  const { data: inserted, error: insertError } = await supabaseAdmin
    .from('idempotency_keys')
    .insert({ key, request_hash: requestHash, status: 'processing' })
    .select()
    .maybeSingle();

  if (inserted && !insertError) {
    return { claimed: true };
  }

  const { data: existing, error: fetchError } = await supabaseAdmin
    .from('idempotency_keys')
    .select('*')
    .eq('key', key)
    .single();

  if (fetchError || !existing) {
    throw insertError ?? fetchError ?? new Error('Failed to claim or read idempotency key');
  }

  return { claimed: false, existing: existing as IdempotencyRecord };
}

export async function completeIdempotencyKey(key: string, status: number, body: unknown) {
  await supabaseAdmin
    .from('idempotency_keys')
    .update({ status: 'completed', response_status: status, response_body: body })
    .eq('key', key);
}

export async function releaseIdempotencyKey(key: string) {
  await supabaseAdmin.from('idempotency_keys').delete().eq('key', key);
}
