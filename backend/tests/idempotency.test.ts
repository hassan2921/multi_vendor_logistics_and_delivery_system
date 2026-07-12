import { fakeSupabase } from './fakeSupabase';

jest.mock('../src/config/supabaseClient', () => ({
  supabaseAdmin: fakeSupabase,
}));

import express from 'express';
import request from 'supertest';
import { requireIdempotencyKey } from '../src/middleware/idempotency.middleware';
import { errorHandler } from '../src/middleware/errorHandler.middleware';
import { claimIdempotencyKey, hashRequest } from '../src/services/idempotency.service';

function buildTestApp() {
  const app = express();
  app.use(express.json());

  let callCount = 0;
  app.post('/widgets', requireIdempotencyKey(), (req, res) => {
    callCount += 1;
    res.status(201).json({ createdCount: callCount, body: req.body });
  });

  app.use(errorHandler);
  return app;
}

describe('idempotency middleware', () => {
  beforeEach(() => {
    fakeSupabase.reset();
  });

  it('rejects requests missing the Idempotency-Key header', async () => {
    const app = buildTestApp();
    const res = await request(app).post('/widgets').send({ name: 'a' });
    expect(res.status).toBe(400);
  });

  it('replays the cached response for a repeated key with the same payload instead of re-running the handler', async () => {
    const app = buildTestApp();
    const key = 'idem-key-1';

    const first = await request(app).post('/widgets').set('Idempotency-Key', key).send({ name: 'a' });
    expect(first.status).toBe(201);
    expect(first.body.createdCount).toBe(1);

    const second = await request(app).post('/widgets').set('Idempotency-Key', key).send({ name: 'a' });
    expect(second.status).toBe(201);
    // Same cached response — handler must NOT have run a second time.
    expect(second.body.createdCount).toBe(1);
  });

  it('returns 422 when the same key is reused with a different payload', async () => {
    const app = buildTestApp();
    const key = 'idem-key-2';

    await request(app).post('/widgets').set('Idempotency-Key', key).send({ name: 'a' });
    const res = await request(app).post('/widgets').set('Idempotency-Key', key).send({ name: 'b' });

    expect(res.status).toBe(422);
  });

  it('distinguishes payloads that differ only inside nested arrays/objects', () => {
    const a = hashRequest('POST', '/orders', {
      vendorId: 'v1',
      items: [{ name: 'Widget', quantity: 1, unit_price_cents: 100 }],
    });
    const b = hashRequest('POST', '/orders', {
      vendorId: 'v1',
      items: [{ name: 'Gadget', quantity: 2, unit_price_cents: 999 }],
    });

    expect(a).not.toBe(b);
  });

  it('hashes identically regardless of key order', () => {
    const a = hashRequest('POST', '/orders', { vendorId: 'v1', items: [{ name: 'W', quantity: 1 }] });
    const b = hashRequest('POST', '/orders', { items: [{ quantity: 1, name: 'W' }], vendorId: 'v1' });

    expect(a).toBe(b);
  });

  it('releases the key on a failed request so the same key can be retried', async () => {
    const app = express();
    app.use(express.json());

    let attempt = 0;
    app.post('/widgets', requireIdempotencyKey(), (req, res, next) => {
      attempt += 1;
      if (attempt === 1) {
        return next(new Error('transient failure'));
      }
      res.status(201).json({ attempt });
    });
    app.use(errorHandler);

    const key = 'idem-key-retry';
    const first = await request(app).post('/widgets').set('Idempotency-Key', key).send({ name: 'a' });
    expect(first.status).toBe(500);

    // settle (release) is fired asynchronously from the res.json wrapper
    await new Promise((resolve) => setTimeout(resolve, 20));

    const second = await request(app).post('/widgets').set('Idempotency-Key', key).send({ name: 'a' });
    expect(second.status).toBe(201);
    expect(second.body.attempt).toBe(2);
  });

  it('returns 409 for a concurrent duplicate request using the same key', async () => {
    const app = buildTestApp();
    const key = 'idem-key-3';

    // Simulate a genuine in-flight duplicate: claim the key directly (as
    // the first request's middleware would) without ever completing it,
    // then send a second request with the same key. The middleware
    // namespaces keys per user ('anon' when unauthenticated).
    await claimIdempotencyKey(`anon:${key}`, hashRequest('POST', '/widgets', { name: 'a' }));

    const res = await request(app).post('/widgets').set('Idempotency-Key', key).send({ name: 'a' });
    expect(res.status).toBe(409);
  });

  it('scopes keys per user — another user reusing the same key never sees the cached response', async () => {
    const app = express();
    app.use(express.json());

    let callCount = 0;
    // Simulated auth: the test picks who is calling via the X-Test-User header.
    app.post(
      '/widgets',
      (req, _res, next) => {
        req.authUser = { id: req.header('X-Test-User')! } as NonNullable<typeof req.authUser>;
        next();
      },
      requireIdempotencyKey(),
      (_req, res) => {
        callCount += 1;
        res.status(201).json({ createdCount: callCount });
      }
    );
    app.use(errorHandler);

    const key = 'shared-key';
    const first = await request(app)
      .post('/widgets').set('Idempotency-Key', key).set('X-Test-User', 'user-A').send({ name: 'a' });
    expect(first.body.createdCount).toBe(1);

    // Identical key AND payload, but a different user: must run the handler
    // again, not replay user A's cached response.
    const second = await request(app)
      .post('/widgets').set('Idempotency-Key', key).set('X-Test-User', 'user-B').send({ name: 'a' });
    expect(second.status).toBe(201);
    expect(second.body.createdCount).toBe(2);
  });
});
