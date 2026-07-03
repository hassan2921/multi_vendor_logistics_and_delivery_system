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

  it('returns 409 for a concurrent duplicate request using the same key', async () => {
    const app = buildTestApp();
    const key = 'idem-key-3';

    // Simulate a genuine in-flight duplicate: claim the key directly (as
    // the first request's middleware would) without ever completing it,
    // then send a second request with the same key.
    await claimIdempotencyKey(key, hashRequest('POST', '/widgets', { name: 'a' }));

    const res = await request(app).post('/widgets').set('Idempotency-Key', key).send({ name: 'a' });
    expect(res.status).toBe(409);
  });
});
