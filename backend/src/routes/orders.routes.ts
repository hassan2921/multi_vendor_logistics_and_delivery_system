import { Router } from 'express';
import * as ordersController from '../controllers/orders.controller';
import * as reviewsController from '../controllers/reviews.controller';
import { requireAuth, requireRole } from '../middleware/auth.middleware';
import { requireIdempotencyKey } from '../middleware/idempotency.middleware';
import { asyncHandler } from '../utils/asyncHandler';

export const ordersRouter = Router();

ordersRouter.post(
  '/',
  requireAuth(),
  requireIdempotencyKey(),
  asyncHandler(ordersController.createOrder)
);

// Price preview — read-only, so no idempotency key needed.
ordersRouter.post('/quote', requireAuth(), asyncHandler(ordersController.quoteOrder));

// Must come before /:id so "mine" isn't parsed as an order id.
ordersRouter.get('/mine', requireAuth(), asyncHandler(ordersController.listMine));

ordersRouter.get('/:id', requireAuth(), asyncHandler(ordersController.getOrder));

ordersRouter.patch(
  '/:id/status',
  requireAuth(),
  requireRole('vendor', 'courier'),
  asyncHandler(ordersController.updateStatus)
);

ordersRouter.post(
  '/:id/claim',
  requireAuth(),
  requireRole('courier'),
  asyncHandler(ordersController.claimDelivery)
);

ordersRouter.post(
  '/:id/cancel',
  requireAuth(),
  requireRole('customer', 'vendor'),
  asyncHandler(ordersController.cancelOrder)
);

ordersRouter.post(
  '/:id/review',
  requireAuth(),
  requireRole('customer'),
  asyncHandler(reviewsController.createReview)
);
