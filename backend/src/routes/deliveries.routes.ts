import { Router } from 'express';
import * as deliveriesController from '../controllers/deliveries.controller';
import { requireAuth, requireRole } from '../middleware/auth.middleware';
import { asyncHandler } from '../utils/asyncHandler';

export const deliveriesRouter = Router();

deliveriesRouter.get(
  '/available',
  requireAuth(),
  requireRole('courier'),
  asyncHandler(deliveriesController.listAvailableJobs)
);
