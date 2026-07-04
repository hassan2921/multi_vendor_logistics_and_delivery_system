import { Router } from 'express';
import * as vendorsController from '../controllers/vendors.controller';
import { requireAuth, requireRole } from '../middleware/auth.middleware';
import { requireIdempotencyKey } from '../middleware/idempotency.middleware';
import { asyncHandler } from '../utils/asyncHandler';

export const vendorsRouter = Router();

vendorsRouter.get('/', asyncHandler(vendorsController.listVendors));

// Onboarding + "my storefront" management — must come before /:vendorId
// routes so "me" isn't parsed as a vendor id.
vendorsRouter.post(
  '/me',
  requireAuth(),
  requireRole('vendor'),
  requireIdempotencyKey(),
  asyncHandler(vendorsController.onboard)
);
vendorsRouter.get('/me', requireAuth(), requireRole('vendor'), asyncHandler(vendorsController.getMyVendor));
vendorsRouter.get(
  '/me/orders',
  requireAuth(),
  requireRole('vendor'),
  asyncHandler(vendorsController.listMyOrders)
);
vendorsRouter.get(
  '/me/products',
  requireAuth(),
  requireRole('vendor'),
  asyncHandler(vendorsController.listMyProducts)
);
vendorsRouter.post(
  '/me/products',
  requireAuth(),
  requireRole('vendor'),
  asyncHandler(vendorsController.createProduct)
);
vendorsRouter.patch(
  '/me/products/:productId',
  requireAuth(),
  requireRole('vendor'),
  asyncHandler(vendorsController.updateProduct)
);

// Public menu browsing for customers.
vendorsRouter.get('/:vendorId/products', asyncHandler(vendorsController.listProducts));
