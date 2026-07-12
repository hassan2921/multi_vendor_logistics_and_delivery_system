import { createSign } from 'crypto';
import { env } from '../config/env';
import { supabaseAdmin } from '../config/supabaseClient';
import type { Order } from '../types/domain';

/**
 * Two-tier notification delivery:
 *
 *  1. Every notification is inserted into the `notifications` table. The app
 *     subscribes to it over Supabase Realtime and raises a local notification
 *     — works with zero external configuration.
 *  2. If FCM credentials are configured (FCM_PROJECT_ID / FCM_CLIENT_EMAIL /
 *     FCM_PRIVATE_KEY from a Firebase service account), the same payload is
 *     also pushed to the user's registered devices so it arrives when the
 *     app is closed. FCM failures are logged, never surfaced to the caller —
 *     a flaky push must not fail an order state change.
 */

export interface NotificationPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export async function registerDeviceToken(
  userId: string,
  token: string,
  platform?: string
): Promise<void> {
  // A device token can migrate between accounts (logout/login on the same
  // phone), so re-registration re-points it at the current user.
  const { data: existing } = await supabaseAdmin
    .from('device_tokens')
    .select('*')
    .eq('token', token)
    .maybeSingle();

  if (existing) {
    await supabaseAdmin
      .from('device_tokens')
      .update({ user_id: userId, platform: platform ?? null, updated_at: new Date().toISOString() })
      .eq('token', token);
    return;
  }

  await supabaseAdmin
    .from('device_tokens')
    .insert({ user_id: userId, token, platform: platform ?? null });
}

export async function notifyUser(userId: string, payload: NotificationPayload): Promise<void> {
  const { error } = await supabaseAdmin.from('notifications').insert({
    user_id: userId,
    title: payload.title,
    body: payload.body,
    data: payload.data ?? null,
  });
  if (error) {
    console.error(`[notifications] inbox insert failed for user ${userId}: ${error.message}`);
  }

  // Fire-and-forget: FCM latency/outages must not block the request path.
  void sendPushToUser(userId, payload).catch((err) =>
    console.error(`[notifications] FCM push failed for user ${userId}:`, err)
  );
}

/** Human-facing messages for each order lifecycle event. */
export async function notifyOrderStatus(order: Order): Promise<void> {
  const orderRef = order.id.slice(0, 8);
  const data = { order_id: order.id, status: order.status };
  const jobs: Promise<void>[] = [];

  const toCustomer = (title: string, body: string) =>
    jobs.push(notifyUser(order.customer_id, { title, body, data }));
  const toVendorOwner = (title: string, body: string) =>
    jobs.push(
      (async () => {
        const { data: vendor } = await supabaseAdmin
          .from('vendors')
          .select('*')
          .eq('id', order.vendor_id)
          .maybeSingle();
        if (vendor?.owner_user_id) {
          await notifyUser(vendor.owner_user_id as string, { title, body, data });
        }
      })()
    );
  const toCourier = (title: string, body: string) => {
    if (order.courier_id) {
      jobs.push(notifyUser(order.courier_id, { title, body, data }));
    }
  };

  switch (order.status) {
    case 'paid':
      toCustomer('Payment confirmed', `Your payment for order #${orderRef} went through.`);
      toVendorOwner('New order', `Order #${orderRef} is paid and waiting for your acceptance.`);
      break;
    case 'accepted':
      toCustomer('Order accepted', `The vendor accepted order #${orderRef}.`);
      break;
    case 'preparing':
      toCustomer('Being prepared', `Order #${orderRef} is being prepared.`);
      break;
    case 'ready_for_pickup':
      toCustomer('Ready for pickup', `Order #${orderRef} is ready — finding you a courier.`);
      break;
    case 'courier_assigned':
      toCustomer('Courier assigned', `A courier is heading to pick up order #${orderRef}.`);
      toCourier('New delivery', `You've been assigned order #${orderRef}.`);
      break;
    case 'picked_up':
      toCustomer('Picked up', `Order #${orderRef} has been picked up.`);
      break;
    case 'in_transit':
      toCustomer('On the way', `Order #${orderRef} is on the way to you.`);
      break;
    case 'delivered':
      toCustomer('Delivered', `Order #${orderRef} was delivered. Enjoy — and rate your order!`);
      toVendorOwner('Order delivered', `Order #${orderRef} was delivered to the customer.`);
      break;
    case 'cancelled':
      toCustomer('Order cancelled', `Order #${orderRef} was cancelled. Any payment will be refunded.`);
      toVendorOwner('Order cancelled', `Order #${orderRef} was cancelled.`);
      break;
    default:
      break;
  }

  await Promise.all(jobs);
}

// ── FCM HTTP v1 (no SDK dependency — plain OAuth2 JWT grant + fetch) ──────

function fcmConfigured(): boolean {
  return Boolean(env.FCM_PROJECT_ID && env.FCM_CLIENT_EMAIL && env.FCM_PRIVATE_KEY);
}

let cachedAccessToken: { token: string; expiresAt: number } | null = null;

async function getFcmAccessToken(): Promise<string> {
  if (cachedAccessToken && Date.now() < cachedAccessToken.expiresAt - 60_000) {
    return cachedAccessToken.token;
  }

  const nowSec = Math.floor(Date.now() / 1000);
  const header = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).toString('base64url');
  const claims = Buffer.from(
    JSON.stringify({
      iss: env.FCM_CLIENT_EMAIL,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: nowSec,
      exp: nowSec + 3600,
    })
  ).toString('base64url');

  const signer = createSign('RSA-SHA256');
  signer.update(`${header}.${claims}`);
  // .env stores the key single-line with literal \n escapes.
  const privateKey = env.FCM_PRIVATE_KEY!.replace(/\\n/g, '\n');
  const signature = signer.sign(privateKey, 'base64url');

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${header}.${claims}.${signature}`,
    }),
  });

  if (!res.ok) {
    throw new Error(`FCM token exchange failed: ${res.status} ${await res.text()}`);
  }
  const json = (await res.json()) as { access_token: string; expires_in: number };
  cachedAccessToken = { token: json.access_token, expiresAt: Date.now() + json.expires_in * 1000 };
  return json.access_token;
}

async function sendPushToUser(userId: string, payload: NotificationPayload): Promise<void> {
  if (!fcmConfigured()) return;

  const { data: tokens } = await supabaseAdmin
    .from('device_tokens')
    .select('*')
    .eq('user_id', userId);

  if (!tokens || tokens.length === 0) return;

  const accessToken = await getFcmAccessToken();

  await Promise.all(
    tokens.map(async (row) => {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${env.FCM_PROJECT_ID}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token: row.token,
              notification: { title: payload.title, body: payload.body },
              data: payload.data ?? {},
            },
          }),
        }
      );

      // Token no longer valid (app uninstalled / token rotated) — prune it.
      if (res.status === 404 || res.status === 410) {
        await supabaseAdmin.from('device_tokens').delete().eq('token', row.token);
      } else if (!res.ok) {
        console.error(`[notifications] FCM send failed: ${res.status} ${await res.text()}`);
      }
    })
  );
}
