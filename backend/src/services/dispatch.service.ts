import { supabaseAdmin } from '../config/supabaseClient';
import type { AppUser, Order } from '../types/domain';
import * as ordersService from './orders.service';
import { haversineKm } from './pricing.service';

/**
 * Automatic courier dispatch.
 *
 * When an order becomes ready_for_pickup we try to assign the nearest
 * available courier immediately. If nobody qualifies the order simply stays
 * in ready_for_pickup and remains visible on the couriers' open-jobs board —
 * auto-dispatch is an accelerator on top of the self-claim marketplace, not
 * a replacement for it.
 */

// A courier whose location report is older than this is treated as offline
// even if they forgot to toggle availability off.
const LOCATION_FRESHNESS_MS = 15 * 60 * 1000;

// Statuses during which a courier already has their hands full.
const COURIER_BUSY_STATUSES = ['courier_assigned', 'picked_up', 'in_transit'];

export async function setCourierAvailability(
  courierId: string,
  params: { isAvailable: boolean; lat?: number; lng?: number }
): Promise<void> {
  const patch: Record<string, unknown> = {
    is_available: params.isAvailable,
    last_seen_at: new Date().toISOString(),
  };
  if (params.lat !== undefined) patch.last_lat = params.lat;
  if (params.lng !== undefined) patch.last_lng = params.lng;

  await supabaseAdmin.from('users').update(patch).eq('id', courierId);
}

interface RankedCourier {
  courier: AppUser;
  distanceKm: number;
}

async function rankAvailableCouriers(pickupLat: number, pickupLng: number): Promise<RankedCourier[]> {
  const { data: couriers } = await supabaseAdmin
    .from('users')
    .select('*')
    .eq('role', 'courier')
    .eq('is_available', true);

  const fresh = ((couriers ?? []) as AppUser[]).filter(
    (c) =>
      c.last_lat != null &&
      c.last_lng != null &&
      c.last_seen_at != null &&
      Date.now() - Date.parse(c.last_seen_at) <= LOCATION_FRESHNESS_MS
  );
  if (fresh.length === 0) return [];

  // Exclude couriers already working an active delivery.
  const { data: activeOrders } = await supabaseAdmin
    .from('orders')
    .select('*')
    .in('courier_id', fresh.map((c) => c.id))
    .in('status', COURIER_BUSY_STATUSES);

  const busyIds = new Set(((activeOrders ?? []) as Order[]).map((o) => o.courier_id));

  return fresh
    .filter((c) => !busyIds.has(c.id))
    .map((c) => ({ courier: c, distanceKm: haversineKm(pickupLat, pickupLng, c.last_lat!, c.last_lng!) }))
    .sort((a, b) => a.distanceKm - b.distanceKm);
}

/**
 * Tries to assign the nearest eligible courier to the order. Returns the
 * updated order on success, or null when no courier could be assigned (no
 * candidates, or the order was claimed in the meantime).
 */
export async function autoAssignCourier(order: Order): Promise<Order | null> {
  const { data: vendor } = await supabaseAdmin
    .from('vendors')
    .select('*')
    .eq('id', order.vendor_id)
    .maybeSingle();

  if (!vendor || vendor.lat == null || vendor.lng == null) {
    return null; // no pickup point to route from
  }

  const ranked = await rankAvailableCouriers(vendor.lat as number, vendor.lng as number);
  if (ranked.length === 0) return null;

  const nearest = ranked[0];
  let assigned: Order;
  try {
    assigned = await ordersService.assignCourier(order.id, nearest.courier.id);
  } catch {
    // Lost the race to a self-claiming courier, or the order moved on —
    // either way the order is in good hands.
    return null;
  }

  // The courier is now committed to this job; stop offering them new ones
  // until they toggle back (delivery completion re-enables them).
  await supabaseAdmin.from('users').update({ is_available: false }).eq('id', nearest.courier.id);
  // assignCourier handles the delivery row and notifications; deliveries.
  // distance_km already holds the vendor→customer route from order creation.
  return assigned;
}

/** Puts a courier back into the dispatch pool after they complete a job. */
export async function releaseCourier(courierId: string): Promise<void> {
  await supabaseAdmin
    .from('users')
    .update({ is_available: true, last_seen_at: new Date().toISOString() })
    .eq('id', courierId);
}
