import express from 'express';

/**
 * Stripe signature verification requires the exact raw request bytes, not the
 * parsed/re-serialized JSON body. This must be mounted on the webhook route
 * BEFORE the global express.json() parser touches it.
 */
export const rawBodyParser = express.raw({ type: 'application/json' });
