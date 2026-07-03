import { Router } from 'express';
import * as paymentsController from '../controllers/payments.controller';
import { requireAuth } from '../middleware/auth.middleware';
import { requireIdempotencyKey } from '../middleware/idempotency.middleware';
import { asyncHandler } from '../utils/asyncHandler';

export const paymentsRouter = Router();

// The /webhook route is intentionally NOT defined here — it's registered
// directly in app.ts, ahead of the global express.json() middleware, because
// Stripe signature verification needs the raw unparsed request body.

paymentsRouter.post(
  '/intent',
  requireAuth(),
  requireIdempotencyKey(),
  asyncHandler(paymentsController.createIntent)
);
