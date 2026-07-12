import Stripe from 'stripe';
import { env } from '../config/env';
import { supabaseAdmin } from '../config/supabaseClient';
import { HttpError } from '../middleware/errorHandler.middleware';
import * as ordersService from './orders.service';

export const stripe = new Stripe(env.STRIPE_SECRET_KEY);

export async function createPaymentIntent(
  orderId: string,
  requestingCustomerId: string
): Promise<{ clientSecret: string }> {
  const order = await ordersService.getOrderById(orderId);

  if (order.customer_id !== requestingCustomerId) {
    throw new HttpError(403, 'You can only pay for your own orders');
  }
  if (order.status !== 'pending_payment') {
    throw new HttpError(422, `Order is not awaiting payment (status: ${order.status})`);
  }

  const paymentIntent = await stripe.paymentIntents.create({
    amount: order.total_cents,
    currency: order.currency,
    metadata: { order_id: order.id },
  });

  const { error } = await supabaseAdmin.from('payments').insert({
    order_id: order.id,
    stripe_payment_intent_id: paymentIntent.id,
    status: paymentIntent.status,
    amount_cents: order.total_cents,
  });

  if (error) {
    throw new HttpError(500, error.message);
  }

  if (!paymentIntent.client_secret) {
    throw new HttpError(500, 'Stripe did not return a client secret');
  }

  return { clientSecret: paymentIntent.client_secret };
}

/**
 * Refunds the order's payment via Stripe if (and only if) it was actually
 * captured. Safe to call after any cancellation, whether or not the order
 * was ever paid — a no-op for orders still in pending_payment.
 */
export async function refundIfPaid(orderId: string): Promise<void> {
  const { data: payment, error } = await supabaseAdmin
    .from('payments')
    .select('*')
    .eq('order_id', orderId)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, error.message);
  }
  if (!payment || payment.status !== 'succeeded' || !payment.stripe_payment_intent_id) {
    return;
  }

  const refund = await stripe.refunds.create({ payment_intent: payment.stripe_payment_intent_id });

  await supabaseAdmin
    .from('payments')
    .update({ status: 'refunded', stripe_refund_id: refund.id, updated_at: new Date().toISOString() })
    .eq('order_id', orderId);
}

export function verifyWebhookSignature(rawBody: Buffer, signature: string): Stripe.Event {
  return stripe.webhooks.constructEvent(rawBody, signature, env.STRIPE_WEBHOOK_SECRET);
}

/**
 * Stripe retries webhook delivery on non-2xx responses, so the same event id
 * can arrive more than once. Recording processed event ids here keeps state
 * transitions from being double-applied.
 */
async function markEventProcessedOnce(eventId: string): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('stripe_events_seen')
    .insert({ event_id: eventId })
    .select()
    .maybeSingle();

  return Boolean(data) && !error;
}

export async function handleWebhookEvent(event: Stripe.Event): Promise<void> {
  const isFirstDelivery = await markEventProcessedOnce(event.id);
  if (!isFirstDelivery) {
    return;
  }

  try {
    await applyEvent(event);
  } catch (err) {
    // Roll back the seen-marker so Stripe's automatic retry of this event
    // isn't skipped — otherwise a transient DB failure here would leave the
    // order permanently unpaid.
    await supabaseAdmin.from('stripe_events_seen').delete().eq('event_id', event.id);
    throw err;
  }
}

async function applyEvent(event: Stripe.Event): Promise<void> {
  switch (event.type) {
    case 'payment_intent.succeeded': {
      const intent = event.data.object as Stripe.PaymentIntent;
      const orderId = intent.metadata.order_id;
      if (!orderId) break;

      await supabaseAdmin
        .from('payments')
        .update({ status: 'succeeded', updated_at: new Date().toISOString() })
        .eq('stripe_payment_intent_id', intent.id);

      await ordersService.updateOrderStatus(orderId, 'paid');
      break;
    }
    case 'payment_intent.payment_failed': {
      const intent = event.data.object as Stripe.PaymentIntent;
      await supabaseAdmin
        .from('payments')
        .update({ status: 'failed', updated_at: new Date().toISOString() })
        .eq('stripe_payment_intent_id', intent.id);
      break;
    }
    default:
      break;
  }
}
