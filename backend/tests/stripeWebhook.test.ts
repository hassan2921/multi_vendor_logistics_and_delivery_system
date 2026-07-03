import { fakeSupabase } from './fakeSupabase';

jest.mock('../src/config/supabaseClient', () => ({
  supabaseAdmin: fakeSupabase,
}));

import Stripe from 'stripe';
import { handleWebhookEvent, stripe, verifyWebhookSignature } from '../src/services/stripe.service';

const WEBHOOK_SECRET = process.env.STRIPE_WEBHOOK_SECRET as string;

function signedPayload(payload: object) {
  const payloadString = JSON.stringify(payload);
  const header = stripe.webhooks.generateTestHeaderString({
    payload: payloadString,
    secret: WEBHOOK_SECRET,
  });
  return { payloadString, header };
}

describe('stripe webhook signature verification', () => {
  it('accepts a correctly signed payload', () => {
    const { payloadString, header } = signedPayload({ id: 'evt_1', type: 'payment_intent.succeeded' });
    const event = verifyWebhookSignature(Buffer.from(payloadString), header);
    expect(event.id).toBe('evt_1');
  });

  it('rejects a payload whose body was tampered with after signing', () => {
    const { header } = signedPayload({ id: 'evt_1', type: 'payment_intent.succeeded' });
    const tampered = Buffer.from(JSON.stringify({ id: 'evt_1', type: 'payment_intent.payment_failed' }));

    expect(() => verifyWebhookSignature(tampered, header)).toThrow();
  });

  it('rejects a payload signed with a different secret', () => {
    const payloadString = JSON.stringify({ id: 'evt_1', type: 'payment_intent.succeeded' });
    const wrongHeader = stripe.webhooks.generateTestHeaderString({
      payload: payloadString,
      secret: 'whsec_totally_different',
    });

    expect(() => verifyWebhookSignature(Buffer.from(payloadString), wrongHeader)).toThrow();
  });
});

describe('stripe webhook event handling', () => {
  beforeEach(() => {
    fakeSupabase.reset();
  });

  function paymentIntentSucceededEvent(eventId: string, orderId: string): Stripe.Event {
    return {
      id: eventId,
      type: 'payment_intent.succeeded',
      data: {
        object: {
          id: 'pi_123',
          metadata: { order_id: orderId },
        },
      },
    } as unknown as Stripe.Event;
  }

  it('marks the order paid on payment_intent.succeeded', async () => {
    await fakeSupabase.from('orders').insert({
      id: 'order-1',
      customer_id: 'cust-1',
      vendor_id: 'vendor-1',
      status: 'pending_payment',
      total_cents: 1000,
      currency: 'usd',
    });
    await fakeSupabase.from('payments').insert({
      order_id: 'order-1',
      stripe_payment_intent_id: 'pi_123',
      status: 'requires_payment_method',
      amount_cents: 1000,
    });

    await handleWebhookEvent(paymentIntentSucceededEvent('evt_A', 'order-1'));

    const { data: order } = await fakeSupabase.from('orders').select('*').eq('id', 'order-1').single();
    expect(order?.status).toBe('paid');
  });

  it('does not re-apply the same event twice (Stripe retry safety)', async () => {
    await fakeSupabase.from('orders').insert({
      id: 'order-2',
      customer_id: 'cust-1',
      vendor_id: 'vendor-1',
      status: 'pending_payment',
      total_cents: 1000,
      currency: 'usd',
    });
    await fakeSupabase.from('payments').insert({
      order_id: 'order-2',
      stripe_payment_intent_id: 'pi_123',
      status: 'requires_payment_method',
      amount_cents: 1000,
    });

    const event = paymentIntentSucceededEvent('evt_B', 'order-2');
    await handleWebhookEvent(event);
    // Manually move the order past 'paid' so a second (incorrect) apply
    // would attempt an illegal transition and throw if dedup didn't work.
    await fakeSupabase.from('orders').update({ status: 'accepted' }).eq('id', 'order-2');

    await expect(handleWebhookEvent(event)).resolves.toBeUndefined();

    const { data: order } = await fakeSupabase.from('orders').select('*').eq('id', 'order-2').single();
    expect(order?.status).toBe('accepted');
  });
});
