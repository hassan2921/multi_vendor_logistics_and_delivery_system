import { Router } from 'express';
import * as adminController from '../controllers/admin.controller';
import { requireAuth, requireRole } from '../middleware/auth.middleware';
import { asyncHandler } from '../utils/asyncHandler';

export const adminRouter = Router();

// Every admin route requires the admin role — no exceptions.
adminRouter.use(requireAuth(), requireRole('admin'));

adminRouter.get('/metrics', asyncHandler(adminController.getMetrics));
adminRouter.get('/vendors', asyncHandler(adminController.listVendors));
adminRouter.patch('/vendors/:vendorId/approval', asyncHandler(adminController.setVendorApproval));
adminRouter.get('/orders', asyncHandler(adminController.listOrders));
adminRouter.get('/promos', asyncHandler(adminController.listPromoCodes));
adminRouter.post('/promos', asyncHandler(adminController.createPromoCode));
adminRouter.patch('/promos/:promoId', asyncHandler(adminController.setPromoCodeActive));
