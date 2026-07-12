import { env } from '../config/env';
import { supabaseAdmin } from '../config/supabaseClient';
import { HttpError } from '../middleware/errorHandler.middleware';
import type { Delivery, Order, Payment, Vendor } from '../types/domain';
import { courierPayoutCents, platformFeeCents } from './pricing.service';
import { stripe } from './stripe.service';

/**
 * Marketplace money movement (Stripe Connect).
 *
 * Split on a delivered order:
 *   vendor   → item subtotal minus the platform commission, transferred to
 *              their Connect account (held on the platform until they finish
 *              Connect onboarding);
 *   courier  → share of the delivery fee + 100% of the tip, recorded on the
 *              delivery row as an earnings ledger (paid out in batches);
 *   platform → the commission + the rest of the delivery fee.
 */

export async function createOnboardingLink(vendor: Vendor): Promise<{ url: string }> {
  let accountId = vendor.stripe_account_id;

  if (!accountId) {
    let account;
    try {
      account = await stripe.accounts.create({
        type: 'express',
        metadata: { vendor_id: vendor.id },
      });
    } catch (err) {
      // A rejected account creation is a platform configuration problem
      // (most commonly Connect not yet enabled on the platform's Stripe
      // account), never something the vendor can act on — surface a clean
      // 503 to them and keep the operator-facing detail in the logs.
      console.error('Stripe Connect account creation failed:', err);
      throw new HttpError(
        503,
        'Payout setup is temporarily unavailable. Please try again later or contact support.'
      );
    }
    accountId = account.id;
    await supabaseAdmin
      .from('vendors')
      .update({ stripe_account_id: accountId })
      .eq('id', vendor.id);
  }

  const link = await stripe.accountLinks.create({
    account: accountId,
    refresh_url: env.CONNECT_REFRESH_URL,
    return_url: env.CONNECT_RETURN_URL,
    type: 'account_onboarding',
  });

  return { url: link.url };
}

export async function refreshConnectStatus(vendor: Vendor): Promise<{ payoutsEnabled: boolean }> {
  if (!vendor.stripe_account_id) {
    return { payoutsEnabled: false };
  }

  const account = await stripe.accounts.retrieve(vendor.stripe_account_id);
  const payoutsEnabled = Boolean(account.charges_enabled && account.payouts_enabled);

  await supabaseAdmin
    .from('vendors')
    .update({ payouts_enabled: payoutsEnabled })
    .eq('id', vendor.id);

  return { payoutsEnabled };
}

/**
 * Settles a delivered order: records the courier's earnings and transfers
 * the vendor's share to their Connect account. Idempotent — a payment that
 * already carries a transfer id is never transferred twice, so this is safe
 * to call from a retried webhook or a double-tapped "delivered" button.
 */
export async function releaseFundsForOrder(orderId: string): Promise<void> {
  const { data: paymentRow } = await supabaseAdmin
    .from('payments')
    .select('*')
    .eq('order_id', orderId)
    .maybeSingle();

  const payment = paymentRow as Payment | null;
  if (!payment || payment.status !== 'succeeded') {
    return; // unpaid orders settle nothing
  }

  const { data: orderRow } = await supabaseAdmin
    .from('orders')
    .select('*')
    .eq('id', orderId)
    .single();
  const order = orderRow as Order | null;
  if (!order) return;

  const subtotal = order.subtotal_cents ?? order.total_cents;
  const platformFee = platformFeeCents(subtotal);
  const vendorShare = subtotal - platformFee;

  // Courier earnings ledger on the delivery row.
  if (order.courier_id) {
    const payout = courierPayoutCents(order.delivery_fee_cents ?? 0, order.tip_cents ?? 0);
    await supabaseAdmin
      .from('deliveries')
      .update({ courier_payout_cents: payout })
      .eq('order_id', order.id);
  }

  if (payment.stripe_transfer_id) {
    return; // already settled
  }

  const { data: vendorRow } = await supabaseAdmin
    .from('vendors')
    .select('*')
    .eq('id', order.vendor_id)
    .maybeSingle();
  const vendor = vendorRow as Vendor | null;

  if (vendor?.stripe_account_id && vendor.payouts_enabled && vendorShare > 0) {
    const transfer = await stripe.transfers.create({
      amount: vendorShare,
      currency: order.currency,
      destination: vendor.stripe_account_id,
      transfer_group: order.id,
      metadata: { order_id: order.id },
    });
    await supabaseAdmin
      .from('payments')
      .update({
        stripe_transfer_id: transfer.id,
        application_fee_cents: platformFee,
        updated_at: new Date().toISOString(),
      })
      .eq('order_id', order.id);
  } else {
    // Vendor hasn't completed Connect onboarding — funds stay on the
    // platform balance; the commission is still recorded for reporting.
    await supabaseAdmin
      .from('payments')
      .update({ application_fee_cents: platformFee, updated_at: new Date().toISOString() })
      .eq('order_id', order.id);
  }
}

export interface CourierEarnings {
  total_cents: number;
  deliveries: Array<Pick<Delivery, 'id' | 'order_id' | 'courier_payout_cents' | 'delivered_at' | 'distance_km'>>;
}

export async function getCourierEarnings(courierId: string): Promise<CourierEarnings> {
  const { data, error } = await supabaseAdmin
    .from('deliveries')
    .select('*')
    .eq('courier_id', courierId)
    .order('delivered_at', { ascending: false });

  if (error) {
    throw new HttpError(500, error.message);
  }

  const earning = ((data ?? []) as Delivery[]).filter((d) => (d.courier_payout_cents ?? 0) > 0);
  return {
    total_cents: earning.reduce((sum, d) => sum + d.courier_payout_cents, 0),
    deliveries: earning.map((d) => ({
      id: d.id,
      order_id: d.order_id,
      courier_payout_cents: d.courier_payout_cents,
      delivered_at: d.delivered_at,
      distance_km: d.distance_km,
    })),
  };
}
