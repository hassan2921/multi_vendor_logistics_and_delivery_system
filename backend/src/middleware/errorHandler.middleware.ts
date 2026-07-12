import type { NextFunction, Request, Response } from 'express';
import Stripe from 'stripe';

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction) {
  if (err instanceof HttpError) {
    return res.status(err.status).json({ error: err.message });
  }

  // body-parser rejections (malformed JSON, oversized payload) arrive as
  // errors with a 4xx `status` — the client's fault, not a 500.
  if (
    err instanceof Error &&
    'status' in err &&
    typeof err.status === 'number' &&
    err.status >= 400 &&
    err.status < 500
  ) {
    return res.status(err.status).json({ error: 'Invalid request body' });
  }

  if (err instanceof Stripe.errors.StripeError) {
    console.error(err);
    // Card declines are the caller's problem (402); anything else — bad
    // platform config, Stripe outage — is an upstream failure (502), but the
    // message is still far more actionable than a blank 500.
    const status = err.type === 'StripeCardError' ? 402 : 502;
    return res.status(status).json({ error: `Payment provider error: ${err.message}` });
  }

  console.error(err);
  return res.status(500).json({ error: 'Internal server error' });
}
