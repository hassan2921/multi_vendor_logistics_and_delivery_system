import { Router } from 'express';
import * as ordersController from '../controllers/orders.controller';
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
