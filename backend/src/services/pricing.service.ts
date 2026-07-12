import { env } from '../config/env';
import { supabaseAdmin } from '../config/supabaseClient';
import { HttpError } from '../middleware/errorHandler.middleware';
import type { PromoCode } from '../types/domain';

const EARTH_RADIUS_KM = 6371;

export function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(a));
}

/**
 * Distance-based delivery fee: base + per-km, capped. A null distance means
 * we couldn't establish a route (either endpoint missing coordinates) — the
 * order is treated as a pickup and charged no delivery fee.
 */
export function deliveryFeeCents(distanceKm: number | null): number {
  if (distanceKm === null) return 0;
  const fee = env.DELIVERY_BASE_FEE_CENTS + Math.round(distanceKm * env.DELIVERY_PER_KM_CENTS);
  return Math.min(fee, env.DELIVERY_FEE_CAP_CENTS);
}

// Vendor prep time plus courier travel at an assumed urban average speed.
const PREP_TIME_MINUTES = 15;
const COURIER_SPEED_KMH = 25;

export function estimateEtaMinutes(distanceKm: number | null): number | null {
  if (distanceKm === null) return null;
  return PREP_TIME_MINUTES + Math.ceil((distanceKm / COURIER_SPEED_KMH) * 60);
}

/**
 * Validates a promo code against the current time, redemption budget, and
 * order subtotal, returning the discount it grants. Throws 422 with a
 * user-presentable message on any failed check — the checkout screen shows
 * these verbatim.
 */
export async function validatePromoCode(
  code: string,
  subtotalCents: number
): Promise<{ promo: PromoCode; discountCents: number }> {
  const normalized = code.trim().toUpperCase();

  const { data, error } = await supabaseAdmin
    .from('promo_codes')
    .select('*')
    .eq('code', normalized)
    .maybeSingle();

  if (error) {
    throw new HttpError(500, error.message);
  }
  const promo = data as PromoCode | null;
  if (!promo || !promo.is_active) {
    throw new HttpError(422, 'Invalid promo code');
  }

  const now = Date.now();
  if (promo.valid_from && now < Date.parse(promo.valid_from)) {
    throw new HttpError(422, 'This promo code is not active yet');
  }
  if (promo.valid_until && now > Date.parse(promo.valid_until)) {
    throw new HttpError(422, 'This promo code has expired');
  }
  if (promo.max_redemptions !== null && promo.redemption_count >= promo.max_redemptions) {
    throw new HttpError(422, 'This promo code has been fully redeemed');
  }
  if (subtotalCents < promo.min_subtotal_cents) {
    throw new HttpError(
      422,
      `Order must be at least $${(promo.min_subtotal_cents / 100).toFixed(2)} to use this code`
    );
  }

  let discountCents =
    promo.discount_type === 'percent'
      ? Math.floor((subtotalCents * promo.discount_value) / 100)
      : promo.discount_value;

  if (promo.max_discount_cents !== null) {
    discountCents = Math.min(discountCents, promo.max_discount_cents);
  }
  // A discount can wipe out the items but never the fees below zero.
  discountCents = Math.min(discountCents, subtotalCents);

  return { promo, discountCents };
}

/**
 * Counts a redemption. Called only after the order row is committed, so an
 * order that fails to persist never burns a redemption.
 */
export async function recordPromoRedemption(promo: PromoCode): Promise<void> {
  await supabaseAdmin
    .from('promo_codes')
    .update({ redemption_count: promo.redemption_count + 1 })
    .eq('id', promo.id);
}

/** Platform commission on the item subtotal; the remainder is the vendor's. */
export function platformFeeCents(subtotalCents: number): number {
  return Math.round((subtotalCents * env.PLATFORM_FEE_PERCENT) / 100);
}

/** Courier compensation: share of the delivery fee plus the full tip. */
export function courierPayoutCents(deliveryFee: number, tipCents: number): number {
  return Math.round((deliveryFee * env.COURIER_DELIVERY_FEE_SHARE_PERCENT) / 100) + tipCents;
}
