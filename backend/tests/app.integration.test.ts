import { fakeSupabase } from './fakeSupabase';

jest.mock('../src/config/supabaseClient', () => ({
  supabaseAdmin: fakeSupabase,
}));

import request from 'supertest';
import { createApp } from '../src/app';

/**
 * Whole-app integration tests: the real middleware chain (helmet, raw-body
 * webhook mount, JSON parsing, auth, error handler) wired exactly as in
 * production, backed by the in-memory Supabase fake.
 */
describe('app integration', () => {
  const app = createApp();

  beforeEach(() => {
    fakeSupabase.reset();
  });

  it('serves /health without auth', async () => {
    const res = await request(app).get('/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
  });

  it('serves the public vendor catalog without auth', async () => {
    const res = await request(app).get('/vendors');
    expect(res.status).toBe(200);
    expect(res.body).toHaveProperty('vendors');
  });

  describe('authentication is enforced on every protected surface', () => {
    const protectedCalls: Array<[string, string]> = [
      ['post', '/orders'],
      ['post', '/orders/quote'],
      ['get', '/orders/mine'],
      ['get', '/orders/some-id'],
      ['patch', '/orders/some-id/status'],
      ['post', '/orders/some-id/claim'],
      ['post', '/orders/some-id/cancel'],
      ['post', '/payments/intent'],
      ['get', '/vendors/me'],
      ['post', '/vendors/me/connect/onboard'],
      ['get', '/vendors/me/connect/status'],
      ['get', '/addresses'],
      ['get', '/notifications'],
      ['get', '/admin/metrics'],
      ['get', '/admin/orders'],
    ];

    it.each(protectedCalls)('%s %s → 401 without a token', async (method, path) => {
      const res = await (request(app) as any)[method](path).send({});
      // Some vendor routes 404 before auth if the path segment doesn't exist;
      // everything listed here must specifically be rejected as unauthenticated.
      expect(res.status).toBe(401);
    });

    it('rejects a garbage bearer token', async () => {
      const res = await request(app)
        .get('/orders/mine')
        .set('Authorization', 'Bearer not-a-real-token');
      expect(res.status).toBe(401);
    });
  });

  describe('stripe webhook endpoint', () => {
    it('rejects a request with no signature header', async () => {
      const res = await request(app)
        .post('/payments/webhook')
        .set('Content-Type', 'application/json')
        .send(JSON.stringify({ id: 'evt_x', type: 'payment_intent.succeeded' }));
      expect(res.status).toBe(400);
      expect(res.body.error).toContain('stripe-signature');
    });

    it('rejects a forged signature', async () => {
      const res = await request(app)
        .post('/payments/webhook')
        .set('Content-Type', 'application/json')
        .set('stripe-signature', 't=1,v1=deadbeef')
        .send(JSON.stringify({ id: 'evt_x', type: 'payment_intent.succeeded' }));
      expect(res.status).toBe(400);
      expect(res.body.error).toContain('signature verification failed');
    });
  });

  it('returns 404 (not a crash) for unknown routes', async () => {
    const res = await request(app).get('/definitely-not-a-route');
    expect(res.status).toBe(404);
  });

  it('handles malformed JSON bodies without a 500', async () => {
    const res = await request(app)
      .post('/auth/register')
      .set('Content-Type', 'application/json')
      .send('{"broken json');
    expect(res.status).toBeGreaterThanOrEqual(400);
    expect(res.status).toBeLessThan(500);
  });
});
