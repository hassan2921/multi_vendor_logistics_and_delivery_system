import { Router } from 'express';
import * as couriersController from '../controllers/couriers.controller';
import { requireAuth, requireRole } from '../middleware/auth.middleware';
import { asyncHandler } from '../utils/asyncHandler';

export const couriersRouter = Router();

couriersRouter.post(
  '/availability',
  requireAuth(),
  requireRole('courier'),
  asyncHandler(couriersController.setAvailability)
);

couriersRouter.get(
  '/earnings',
  requireAuth(),
  requireRole('courier'),
  asyncHandler(couriersController.getEarnings)
);
