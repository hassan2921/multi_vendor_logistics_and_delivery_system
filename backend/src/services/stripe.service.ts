import Stripe from 'stripe';
import { env } from '../config/env';
import { supabaseAdmin } from '../config/supabaseClient';
import { HttpError } from '../middleware/errorHandler.middleware';
import * as ordersService from './orders.service';

export const stripe = new Stripe(env.STRIPE_SECRET_KEY);

export async function createPaymentIntent(orderId: string): Promise<{ clientSecret: string }> {
  const order = await ordersService.getOrderById(orderId);

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
