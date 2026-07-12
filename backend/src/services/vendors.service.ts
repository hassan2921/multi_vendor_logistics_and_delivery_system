import { supabaseAdmin } from '../config/supabaseClient';
import type { Order, Product, Vendor } from '../types/domain';
import { HttpError } from '../middleware/errorHandler.middleware';

export interface VendorSearchFilters {
  search?: string;
  category?: string;
  minRating?: number;
  sort?: 'rating' | 'name';
}

/** Storefront discovery: only active AND admin-approved vendors are listed. */
export async function listActiveVendors(filters: VendorSearchFilters = {}): Promise<Vendor[]> {
  let query = supabaseAdmin
    .from('vendors')
    .select('*')
    .eq('is_active', true)
    .eq('approval_status', 'approved');

  if (filters.search) {
    query = query.ilike('name', `%${filters.search}%`);
  }
  if (filters.category) {
    query = query.eq('category', filters.category);
  }
  if (filters.minRating !== undefined) {
    query = query.gte('rating_avg', filters.minRating);
  }
  query =
    filters.sort === 'rating'
      ? query.order('rating_avg', { ascending: false })
      : query.order('name', { ascending: true });

  const { data, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []) as Vendor[];
}

export async function getVendorById(vendorId: string): Promise<Vendor> {
  const { data, error } = await supabaseAdmin
    .from('vendors')
    .select('*')
    .eq('id', vendorId)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, error.message);
  }
  if (!data) {
    throw new HttpError(404, 'Vendor not found');
  }
  return data as Vendor;
}

export async function getVendorByOwner(ownerUserId: string): Promise<Vendor | null> {
  const { data, error } = await supabaseAdmin
    .from('vendors')
    .select('*')
    .eq('owner_user_id', ownerUserId)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data as Vendor) ?? null;
}

/**
 * Creates the vendor's storefront row on first onboarding, or returns the
 * existing one — safe to call repeatedly (e.g. if the app retries after a
 * dropped response). The unique constraint on vendors.owner_user_id is what
 * makes this idempotent under a concurrent double-submit.
 */
export async function createOrGetVendorForOwner(
  ownerUserId: string,
  params: { name: string; address?: string; lat?: number; lng?: number; imageUrl?: string }
): Promise<Vendor> {
  const existing = await getVendorByOwner(ownerUserId);
  if (existing) return existing;

  const { data, error } = await supabaseAdmin
    .from('vendors')
    .insert({
      owner_user_id: ownerUserId,
      name: params.name,
      address: params.address ?? null,
      lat: params.lat ?? null,
      lng: params.lng ?? null,
      image_url: params.imageUrl ?? null,
    })
    .select()
    .single();

  if (error || !data) {
    // Unique-constraint race: someone else's concurrent onboarding call won.
    const fallback = await getVendorByOwner(ownerUserId);
    if (fallback) return fallback;
    throw new HttpError(400, error?.message ?? 'Failed to create vendor');
  }

  return data as Vendor;
}

export async function updateVendorProfile(
  vendorId: string,
  updates: Partial<{
    name: string;
    address: string | null;
    imageUrl: string | null;
  }>
): Promise<Vendor> {
  const patch: Record<string, unknown> = {};
  if (updates.name !== undefined) patch.name = updates.name;
  if (updates.address !== undefined) patch.address = updates.address;
  if (updates.imageUrl !== undefined) patch.image_url = updates.imageUrl;

  const { data, error } = await supabaseAdmin
    .from('vendors')
    .update(patch)
    .eq('id', vendorId) // caller resolves ownership via requireOwnVendor
    .select()
    .maybeSingle();

  if (error) {
    throw new HttpError(400, error.message);
  }
  if (!data) {
    throw new HttpError(404, 'Vendor not found');
  }
  return data as Vendor;
}

export async function listOrdersForVendor(vendorId: string): Promise<Order[]> {
  const { data, error } = await supabaseAdmin
    .from('orders')
    .select('*')
    .eq('vendor_id', vendorId)
    .order('created_at', { ascending: false });

  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []) as Order[];
}

export async function listProductsForVendor(
  vendorId: string,
  opts: { onlyAvailable?: boolean; search?: string; category?: string } = {}
): Promise<Product[]> {
  let query = supabaseAdmin.from('products').select('*').eq('vendor_id', vendorId);
  if (opts.onlyAvailable) {
    query = query.eq('is_available', true);
  }
  if (opts.search) {
    query = query.ilike('name', `%${opts.search}%`);
  }
  if (opts.category) {
    query = query.eq('category', opts.category);
  }

  const { data, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []) as Product[];
}

export async function getProductsByIds(ids: string[]): Promise<Product[]> {
  if (ids.length === 0) return [];
  const { data, error } = await supabaseAdmin.from('products').select('*').in('id', ids);
  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []) as Product[];
}

export async function createProduct(
  vendorId: string,
  params: {
    name: string;
    description?: string;
    priceCents: number;
    category?: string;
    stockQuantity?: number;
    imageUrl?: string;
  }
): Promise<Product> {
  const { data, error } = await supabaseAdmin
    .from('products')
    .insert({
      vendor_id: vendorId,
      name: params.name,
      description: params.description ?? null,
      price_cents: params.priceCents,
      is_available: true,
      category: params.category ?? null,
      // undefined = inventory not tracked → stored as null
      stock_quantity: params.stockQuantity ?? null,
      image_url: params.imageUrl ?? null,
    })
    .select()
    .single();

  if (error || !data) {
    throw new HttpError(400, error?.message ?? 'Failed to create product');
  }
  return data as Product;
}

export async function updateProduct(
  vendorId: string,
  productId: string,
  updates: Partial<{
    name: string;
    description: string | null;
    priceCents: number;
    isAvailable: boolean;
    category: string | null;
    stockQuantity: number | null;
    imageUrl: string | null;
  }>
): Promise<Product> {
  const patch: Record<string, unknown> = {};
  if (updates.name !== undefined) patch.name = updates.name;
  if (updates.description !== undefined) patch.description = updates.description;
  if (updates.priceCents !== undefined) patch.price_cents = updates.priceCents;
  if (updates.isAvailable !== undefined) patch.is_available = updates.isAvailable;
  if (updates.category !== undefined) patch.category = updates.category;
  if (updates.stockQuantity !== undefined) patch.stock_quantity = updates.stockQuantity;
  if (updates.imageUrl !== undefined) patch.image_url = updates.imageUrl;

  const { data, error } = await supabaseAdmin
    .from('products')
    .update(patch)
    .eq('id', productId)
    .eq('vendor_id', vendorId) // ownership check baked into the query itself
    .select()
    .maybeSingle();

  if (error) {
    throw new HttpError(400, error.message);
  }
  if (!data) {
    throw new HttpError(404, 'Product not found for this vendor');
  }
  return data as Product;
}
