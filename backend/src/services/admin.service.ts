import { supabaseAdmin } from '../config/supabaseClient';
import { HttpError } from '../middleware/errorHandler.middleware';
import type { Order, PromoCode, Vendor, VendorApprovalStatus } from '../types/domain';

// ── vendor approval workflow ───────────────────────────────────────────────

export async function listVendors(status?: VendorApprovalStatus): Promise<Vendor[]> {
  let query = supabaseAdmin.from('vendors').select('*').order('created_at', { ascending: false });
  if (status) {
    query = query.eq('approval_status', status);
  }
  const { data, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []) as Vendor[];
}

export async function setVendorApproval(
  vendorId: string,
  status: VendorApprovalStatus
): Promise<Vendor> {
  const { data, error } = await supabaseAdmin
    .from('vendors')
    .update({ approval_status: status })
    .eq('id', vendorId)
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

// ── platform-wide order overview ───────────────────────────────────────────

export async function listAllOrders(opts: { status?: string; limit?: number } = {}): Promise<Order[]> {
  let query = supabaseAdmin
    .from('orders')
    .select('*')
    .order('created_at', { ascending: false })
    .limit(opts.limit ?? 100);

  if (opts.status) {
    query = query.eq('status', opts.status);
  }
  const { data, error } = await query;
  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []) as Order[];
}

// ── metrics ────────────────────────────────────────────────────────────────

export interface PlatformMetrics {
  orders_total: number;
  orders_delivered: number;
  orders_cancelled: number;
  gmv_cents: number;
  platform_fees_cents: number;
  vendors_pending_approval: number;
  active_couriers: number;
}

export async function getMetrics(): Promise<PlatformMetrics> {
  const [orders, payments, pendingVendors, couriers] = await Promise.all([
    supabaseAdmin.from('orders').select('*'),
    supabaseAdmin.from('payments').select('*').eq('status', 'succeeded'),
    supabaseAdmin.from('vendors').select('*').eq('approval_status', 'pending'),
    supabaseAdmin.from('users').select('*').eq('role', 'courier').eq('is_available', true),
  ]);

  const allOrders = (orders.data ?? []) as Order[];
  const paid = (payments.data ?? []) as Array<{ amount_cents: number; application_fee_cents: number }>;

  return {
    orders_total: allOrders.length,
    orders_delivered: allOrders.filter((o) => o.status === 'delivered').length,
    orders_cancelled: allOrders.filter((o) => o.status === 'cancelled').length,
    gmv_cents: paid.reduce((sum, p) => sum + (p.amount_cents ?? 0), 0),
    platform_fees_cents: paid.reduce((sum, p) => sum + (p.application_fee_cents ?? 0), 0),
    vendors_pending_approval: (pendingVendors.data ?? []).length,
    active_couriers: (couriers.data ?? []).length,
  };
}

// ── promo code management ──────────────────────────────────────────────────

export async function listPromoCodes(): Promise<PromoCode[]> {
  const { data, error } = await supabaseAdmin
    .from('promo_codes')
    .select('*')
    .order('created_at', { ascending: false });

  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []) as PromoCode[];
}

export async function createPromoCode(params: {
  code: string;
  description?: string;
  discountType: 'percent' | 'fixed';
  discountValue: number;
  minSubtotalCents?: number;
  maxDiscountCents?: number;
  validFrom?: string;
  validUntil?: string;
  maxRedemptions?: number;
}): Promise<PromoCode> {
  const { data, error } = await supabaseAdmin
    .from('promo_codes')
    .insert({
      code: params.code.trim().toUpperCase(),
      description: params.description ?? null,
      discount_type: params.discountType,
      discount_value: params.discountValue,
      min_subtotal_cents: params.minSubtotalCents ?? 0,
      max_discount_cents: params.maxDiscountCents ?? null,
      valid_from: params.validFrom ?? null,
      valid_until: params.validUntil ?? null,
      max_redemptions: params.maxRedemptions ?? null,
    })
    .select()
    .single();

  if (error || !data) {
    if (error?.message.includes('duplicate') || error?.message.includes('unique')) {
      throw new HttpError(409, 'A promo code with that code already exists');
    }
    throw new HttpError(400, error?.message ?? 'Failed to create promo code');
  }
  return data as PromoCode;
}

export async function setPromoCodeActive(promoId: string, isActive: boolean): Promise<PromoCode> {
  const { data, error } = await supabaseAdmin
    .from('promo_codes')
    .update({ is_active: isActive })
    .eq('id', promoId)
    .select()
    .maybeSingle();

  if (error) {
    throw new HttpError(400, error.message);
  }
  if (!data) {
    throw new HttpError(404, 'Promo code not found');
  }
  return data as PromoCode;
}
