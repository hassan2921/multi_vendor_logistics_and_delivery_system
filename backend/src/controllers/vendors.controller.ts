import type { Request, Response } from 'express';
import { z } from 'zod';
import { HttpError } from '../middleware/errorHandler.middleware';
import * as vendorsService from '../services/vendors.service';

export async function listVendors(_req: Request, res: Response) {
  const vendors = await vendorsService.listActiveVendors();
  res.json({ vendors });
}

export async function listProducts(req: Request, res: Response) {
  const products = await vendorsService.listProductsForVendor(req.params.vendorId, { onlyAvailable: true });
  res.json({ products });
}

const onboardSchema = z.object({
  name: z.string().min(1),
  address: z.string().optional(),
  lat: z.number().optional(),
  lng: z.number().optional(),
});

export async function onboard(req: Request, res: Response) {
  if (req.authUser?.role !== 'vendor') {
    throw new HttpError(403, 'Only vendor accounts can create a storefront');
  }
  const parsed = onboardSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }

  const vendor = await vendorsService.createOrGetVendorForOwner(req.authUser.id, parsed.data);
  res.status(201).json({ vendor });
}

async function requireOwnVendor(req: Request) {
  if (req.authUser?.role !== 'vendor') {
    throw new HttpError(403, 'Only vendor accounts can do this');
  }
  const vendor = await vendorsService.getVendorByOwner(req.authUser.id);
  if (!vendor) {
    throw new HttpError(404, 'No storefront found — onboard first via POST /vendors/me');
  }
  return vendor;
}

export async function getMyVendor(req: Request, res: Response) {
  const vendor = await requireOwnVendor(req);
  res.json({ vendor });
}

export async function listMyOrders(req: Request, res: Response) {
  const vendor = await requireOwnVendor(req);
  const orders = await vendorsService.listOrdersForVendor(vendor.id);
  res.json({ orders });
}

export async function listMyProducts(req: Request, res: Response) {
  const vendor = await requireOwnVendor(req);
  const products = await vendorsService.listProductsForVendor(vendor.id);
  res.json({ products });
}

const createProductSchema = z.object({
  name: z.string().min(1),
  description: z.string().optional(),
  priceCents: z.number().int().nonnegative(),
});

export async function createProduct(req: Request, res: Response) {
  const vendor = await requireOwnVendor(req);
  const parsed = createProductSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }

  const product = await vendorsService.createProduct(vendor.id, parsed.data);
  res.status(201).json({ product });
}

const updateProductSchema = z.object({
  name: z.string().min(1).optional(),
  description: z.string().nullable().optional(),
  priceCents: z.number().int().nonnegative().optional(),
  isAvailable: z.boolean().optional(),
});

export async function updateProduct(req: Request, res: Response) {
  const vendor = await requireOwnVendor(req);
  const parsed = updateProductSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }

  const product = await vendorsService.updateProduct(vendor.id, req.params.productId, parsed.data);
  res.json({ product });
}
