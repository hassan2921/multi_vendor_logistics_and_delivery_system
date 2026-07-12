import type { Request, Response } from 'express';
import { z } from 'zod';
import { HttpError } from '../middleware/errorHandler.middleware';
import * as payoutsService from '../services/payouts.service';
import * as vendorsService from '../services/vendors.service';

export async function listVendors(req: Request, res: Response) {
  const q = req.query;
  const vendors = await vendorsService.listActiveVendors({
    search: typeof q.search === 'string' ? q.search : undefined,
    category: typeof q.category === 'string' ? q.category : undefined,
    minRating: typeof q.minRating === 'string' ? Number(q.minRating) : undefined,
    sort: q.sort === 'rating' ? 'rating' : undefined,
  });
  res.json({ vendors });
}

export async function listProducts(req: Request, res: Response) {
  const q = req.query;
  const products = await vendorsService.listProductsForVendor(req.params.vendorId, {
    onlyAvailable: true,
    search: typeof q.search === 'string' ? q.search : undefined,
    category: typeof q.category === 'string' ? q.category : undefined,
  });
  res.json({ products });
}

const onboardSchema = z.object({
  name: z.string().min(1),
  address: z.string().optional(),
  lat: z.number().optional(),
  lng: z.number().optional(),
  imageUrl: z.string().url().optional(),
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

const updateVendorSchema = z.object({
  name: z.string().min(1).optional(),
  address: z.string().nullable().optional(),
  imageUrl: z.string().url().nullable().optional(),
});

export async function updateMyVendor(req: Request, res: Response) {
  const vendor = await requireOwnVendor(req);
  const parsed = updateVendorSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }

  const updated = await vendorsService.updateVendorProfile(vendor.id, parsed.data);
  res.json({ vendor: updated });
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
  category: z.string().optional(),
  stockQuantity: z.number().int().nonnegative().optional(),
  imageUrl: z.string().url().optional(),
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
  category: z.string().nullable().optional(),
  stockQuantity: z.number().int().nonnegative().nullable().optional(),
  imageUrl: z.string().url().nullable().optional(),
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

// ── Stripe Connect payouts ─────────────────────────────────────────────────

export async function createConnectOnboardingLink(req: Request, res: Response) {
  const vendor = await requireOwnVendor(req);
  const { url } = await payoutsService.createOnboardingLink(vendor);
  res.json({ url });
}

export async function getConnectStatus(req: Request, res: Response) {
  const vendor = await requireOwnVendor(req);
  const { payoutsEnabled } = await payoutsService.refreshConnectStatus(vendor);
  res.json({ payoutsEnabled, stripeAccountId: vendor.stripe_account_id });
}
