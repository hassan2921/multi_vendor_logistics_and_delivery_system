import { fakeSupabase } from './fakeSupabase';

jest.mock('../src/config/supabaseClient', () => ({
  supabaseAdmin: fakeSupabase,
}));

import express from 'express';
import request from 'supertest';
import Stripe from 'stripe';
import { errorHandler } from '../src/middleware/errorHandler.middleware';
import { createPaymentIntent, stripe } from '../src/services/stripe.service';

describe('createPaymentIntent authorization', () => {
  beforeEach(async () => {
    fakeSupabase.reset();
    await fakeSupabase.from('orders').insert({
      id: 'order-1',
      customer_id: 'cust-1',
      vendor_id: 'vendor-1',
      status: 'pending_payment',
      total_cents: 1000,
      currency: 'usd',
    });
  });

  it("rejects paying for another customer's order", async () => {
    await expect(createPaymentIntent('order-1', 'cust-OTHER')).rejects.toMatchObject({ status: 403 });
  });

  it('creates an intent for the order owner', async () => {
    const createSpy = jest.spyOn(stripe.paymentIntents, 'create').mockResolvedValue({
      id: 'pi_1',
      status: 'requires_payment_method',
      client_secret: 'pi_1_secret',
    } as unknown as Stripe.Response<Stripe.PaymentIntent>);

    const { clientSecret } = await createPaymentIntent('order-1', 'cust-1');
    expect(clientSecret).toBe('pi_1_secret');
    expect(createSpy).toHaveBeenCalledWith(
      expect.objectContaining({ amount: 1000, metadata: { order_id: 'order-1' } })
    );
    createSpy.mockRestore();
  });

  it('rejects when the order is not awaiting payment', async () => {
    await fakeSupabase.from('orders').update({ status: 'paid' }).eq('id', 'order-1');
    await expect(createPaymentIntent('order-1', 'cust-1')).rejects.toMatchObject({ status: 422 });
  });
});

describe('errorHandler Stripe error mapping', () => {
  function appThrowing(err: unknown) {
    const app = express();
    app.get('/boom', (_req, _res, next) => next(err));
    app.use(errorHandler);
    return app;
  }

  it('maps card errors to 402 with the Stripe message', async () => {
    const err = new Stripe.errors.StripeCardError({
      type: 'card_error',
      message: 'Your card was declined.',
    } as Stripe.StripeRawError);

    const res = await request(appThrowing(err)).get('/boom');
    expect(res.status).toBe(402);
    expect(res.body.error).toContain('Your card was declined.');
  });

  it('maps other Stripe errors to 502 instead of a blank 500', async () => {
    const err = new Stripe.errors.StripeInvalidRequestError({
      type: 'invalid_request_error',
      message: 'Connect is not enabled on this account.',
    } as Stripe.StripeRawError);

    const res = await request(appThrowing(err)).get('/boom');
    expect(res.status).toBe(502);
    expect(res.body.error).toContain('Connect is not enabled');
  });

  it('still hides non-Stripe internal errors behind a generic 500', async () => {
    jest.spyOn(console, 'error').mockImplementation(() => undefined);
    const res = await request(appThrowing(new Error('secret database detail'))).get('/boom');
    expect(res.status).toBe(500);
    expect(res.body.error).toBe('Internal server error');
    (console.error as jest.Mock).mockRestore();
  });
});
