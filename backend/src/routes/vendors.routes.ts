import { Router } from 'express';
import * as vendorsController from '../controllers/vendors.controller';
import { requireAuth } from '../middleware/auth.middleware';
import { asyncHandler } from '../utils/asyncHandler';

export const vendorsRouter = Router();

vendorsRouter.get('/', asyncHandler(vendorsController.listVendors));
vendorsRouter.get('/:vendorId/orders', requireAuth(), asyncHandler(vendorsController.listVendorOrders));
