import type { Request, Response } from 'express';
import { HttpError } from '../middleware/errorHandler.middleware';
import * as vendorsService from '../services/vendors.service';

export async function listVendors(_req: Request, res: Response) {
  const vendors = await vendorsService.listActiveVendors();
  res.json({ vendors });
}

export async function listVendorOrders(req: Request, res: Response) {
  if (req.authUser?.role !== 'vendor') {
    throw new HttpError(403, 'Only vendors can view their orders');
  }
  const orders = await vendorsService.listOrdersForVendor(req.params.vendorId);
  res.json({ orders });
}
