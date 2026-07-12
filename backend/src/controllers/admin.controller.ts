import type { Request, Response } from 'express';
import { z } from 'zod';
import { HttpError } from '../middleware/errorHandler.middleware';
import * as adminService from '../services/admin.service';

export async function getMetrics(_req: Request, res: Response) {
  const metrics = await adminService.getMetrics();
  res.json({ metrics });
}

const approvalStatusSchema = z.enum(['pending', 'approved', 'rejected']);

export async function listVendors(req: Request, res: Response) {
  const status = req.query.status ? approvalStatusSchema.parse(req.query.status) : undefined;
  const vendors = await adminService.listVendors(status);
  res.json({ vendors });
}

export async function setVendorApproval(req: Request, res: Response) {
  const parsed = z.object({ status: approvalStatusSchema }).safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, 'status must be pending, approved, or rejected');
  }
  const vendor = await adminService.setVendorApproval(req.params.vendorId, parsed.data.status);
  res.json({ vendor });
}

export async function listOrders(req: Request, res: Response) {
  const orders = await adminService.listAllOrders({
    status: typeof req.query.status === 'string' ? req.query.status : undefined,
    limit: req.query.limit ? Number(req.query.limit) : undefined,
  });
  res.json({ orders });
}

export async function listPromoCodes(_req: Request, res: Response) {
  const promoCodes = await adminService.listPromoCodes();
  res.json({ promoCodes });
}

const createPromoSchema = z.object({
  code: z.string().min(2).max(32),
  description: z.string().optional(),
  discountType: z.enum(['percent', 'fixed']),
  discountValue: z.number().int().positive(),
  minSubtotalCents: z.number().int().nonnegative().optional(),
  maxDiscountCents: z.number().int().positive().optional(),
  validFrom: z.string().datetime().optional(),
  validUntil: z.string().datetime().optional(),
  maxRedemptions: z.number().int().positive().optional(),
});

export async function createPromoCode(req: Request, res: Response) {
  const parsed = createPromoSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }
  if (parsed.data.discountType === 'percent' && parsed.data.discountValue > 100) {
    throw new HttpError(400, 'Percent discounts cannot exceed 100');
  }
  const promoCode = await adminService.createPromoCode(parsed.data);
  res.status(201).json({ promoCode });
}

export async function setPromoCodeActive(req: Request, res: Response) {
  const parsed = z.object({ isActive: z.boolean() }).safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, 'isActive must be a boolean');
  }
  const promoCode = await adminService.setPromoCodeActive(req.params.promoId, parsed.data.isActive);
  res.json({ promoCode });
}
