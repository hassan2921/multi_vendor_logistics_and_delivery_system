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
    const key = req.header('Idempotency-Key');
    if (!key) {
      return res.status(400).json({ error: 'Idempotency-Key header is required' });
    }

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

    // Intercept res.json so we can cache the response and mark this key completed.
    const originalJson = res.json.bind(res);
    res.json = ((body: unknown) => {
      completeIdempotencyKey(key, res.statusCode, body).catch((err) =>
        console.error('Failed to persist idempotency response', err)
      );
      return originalJson(body);
    }) as typeof res.json;

    res.on('error', () => {
      releaseIdempotencyKey(key).catch((err) => console.error('Failed to release idempotency key', err));
    });

    next();
  };
}
