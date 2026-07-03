import { fakeSupabase } from './fakeSupabase';

jest.mock('../src/config/supabaseClient', () => ({
  supabaseAdmin: fakeSupabase,
}));

import express from 'express';
import request from 'supertest';
import { requireIdempotencyKey } from '../src/middleware/idempotency.middleware';
import { errorHandler } from '../src/middleware/errorHandler.middleware';

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

  it('returns 409 for a concurrent duplicate request using the same key', async () => {
    const app = buildTestApp();
    const key = 'idem-key-3';

    // First request claims the key but its handler never resolves before
    // the second request checks, simulating a genuine in-flight duplicate.
    const slowApp = express();
    slowApp.use(express.json());
    slowApp.post('/widgets', requireIdempotencyKey(), () => {
      // never respond — leaves the key permanently in 'processing'
    });
    slowApp.use(errorHandler);

    request(slowApp).post('/widgets').set('Idempotency-Key', key).send({ name: 'a' });
    // give the first request a moment to claim the key
    await new Promise((resolve) => setTimeout(resolve, 20));

    const res = await request(app).post('/widgets').set('Idempotency-Key', key).send({ name: 'a' });
    expect(res.status).toBe(409);
  });
});
