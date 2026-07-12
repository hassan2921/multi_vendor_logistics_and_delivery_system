import type { NextFunction, Request, Response } from 'express';
import {
  claimIdempotencyKey,
  completeIdempotencyKey,
  hashRequest,
  releaseIdempotencyKey,
} from '../services/idempotency.service';

/**
 * Guards against duplicate order/payment-intent creation caused by
 * double-taps or client retries after a dropped network response.
 *
 * The Postgres unique-constraint insert in claimIdempotencyKey acts as the
 * lock, so this is safe under concurrent requests without a separate
 * distributed-lock service.
 */
export function requireIdempotencyKey() {
  return async (req: Request, res: Response, next: NextFunction) => {
    const clientKey = req.header('Idempotency-Key');
    if (!clientKey) {
      return res.status(400).json({ error: 'Idempotency-Key header is required' });
    }

    // Namespace per user: without this, two users sending the same key would
    // share one record — the second could be served the first's cached
    // response (someone else's order, address and all) or a spurious 409.
    const key = `${req.authUser?.id ?? 'anon'}:${clientKey}`;

    const requestHash = hashRequest(req.method, req.path, req.body);

    let claim;
    try {
      claim = await claimIdempotencyKey(key, requestHash);
    } catch (err) {
      return next(err);
    }

    if (!claim.claimed) {
      const existing = claim.existing;
      if (existing.request_hash !== requestHash) {
        return res.status(422).json({ error: 'Idempotency-Key reused with a different request payload' });
      }
      if (existing.status === 'completed') {
        return res.status(existing.response_status ?? 200).json(existing.response_body);
      }
      return res.status(409).json({ error: 'A request with this Idempotency-Key is already in progress' });
    }

    // Intercept res.json: cache successful responses for replay, but
    // release the key on error responses so the client can retry a
    // legitimately-failed request with the same key. This also covers
    // controller exceptions — the errorHandler's res.json goes through
    // this same wrapper.
    const originalJson = res.json.bind(res);
    res.json = ((body: unknown) => {
      const settle = res.statusCode < 400
        ? completeIdempotencyKey(key, res.statusCode, body)
        : releaseIdempotencyKey(key);
      settle.catch((err) => console.error('Failed to settle idempotency key', err));
      return originalJson(body);
    }) as typeof res.json;

    next();
  };
}
