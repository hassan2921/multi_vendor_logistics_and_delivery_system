import { supabaseAdmin } from '../config/supabaseClient';
import type { Order, OrderItemSelection, OrderQuote, OrderStatus, PromoCode, UserRole } from '../types/domain';
import { HttpError } from '../middleware/errorHandler.middleware';
import { getProductsByIds, getVendorById, getVendorByOwner } from './vendors.service';
import * as pricing from './pricing.service';
// Namespace imports (not destructured) on purpose: orders ↔ dispatch/payouts
// form require cycles, and property access at call time is what keeps them
// safe under CommonJS.
import * as dispatchService from './dispatch.service';
import * as notificationsService from './notifications.service';
import * as payoutsService from './payouts.service';

interface OrderPricingParams {
  vendorId: string;
  items: OrderItemSelection[];
  deliveryLat?: number;
  deliveryLng?: number;
  tipCents?: number;
  promoCode?: string;
}

interface PricedOrder {
  quote: OrderQuote;
  promo: PromoCode | null;
  lineItems: Array<{ product_id: string; name: string; quantity: number; unit_price_cents: number }>;
  /** Products whose inventory is tracked and must be reserved at checkout. */
  trackedProductIds: Set<string>;
}

/**
 * Shared by the quote endpoint and order creation so the preview a customer
 * sees at checkout is byte-for-byte the price they are charged. Priced
 * entirely from the catalog — the client only ever sends product ids and
 * quantities, never a price, so a tampered client can't discount its own
 * order.
 */
async function priceOrder(params: OrderPricingParams): Promise<PricedOrder> {
  if (params.items.length === 0) {
    throw new HttpError(400, 'Order must contain at least one item');
  }

  const vendor = await getVendorById(params.vendorId);
  if (!vendor.is_active || vendor.approval_status !== 'approved') {
    throw new HttpError(422, 'This vendor is not currently accepting orders');
  }

  const products = await getProductsByIds(params.items.map((item) => item.productId));
  const productsById = new Map(products.map((p) => [p.id, p]));

  const lineItems = params.items.map((item) => {
    if (item.quantity < 1) {
      throw new HttpError(400, 'Quantity must be at least 1');
    }
    const product = productsById.get(item.productId);
    if (!product) {
      throw new HttpError(400, `Unknown product: ${item.productId}`);
    }
    if (product.vendor_id !== params.vendorId) {
      throw new HttpError(422, `${product.name} does not belong to the selected vendor`);
    }
    if (!product.is_available) {
      throw new HttpError(422, `${product.name} is not currently available`);
    }
    // == null on purpose: a missing column and SQL NULL both mean untracked.
    if (product.stock_quantity != null && product.stock_quantity < item.quantity) {
      throw new HttpError(422, `Only ${product.stock_quantity} of ${product.name} left in stock`);
    }
    return {
      product_id: product.id,
      name: product.name,
      quantity: item.quantity,
      unit_price_cents: product.price_cents,
    };
  });

  const subtotalCents = lineItems.reduce((sum, li) => sum + li.quantity * li.unit_price_cents, 0);

  const distanceKm =
    vendor.lat != null && vendor.lng != null && params.deliveryLat != null && params.deliveryLng != null
      ? pricing.haversineKm(vendor.lat, vendor.lng, params.deliveryLat, params.deliveryLng)
      : null;
  const deliveryFeeCents = pricing.deliveryFeeCents(distanceKm);
  const etaMinutes = pricing.estimateEtaMinutes(distanceKm);

  const tipCents = params.tipCents ?? 0;
  if (tipCents < 0 || !Number.isInteger(tipCents)) {
    throw new HttpError(400, 'Tip must be a non-negative whole number of cents');
  }

  let promo: PromoCode | null = null;
  let discountCents = 0;
  if (params.promoCode) {
    ({ promo, discountCents } = await pricing.validatePromoCode(params.promoCode, subtotalCents));
  }

  return {
    quote: {
      subtotal_cents: subtotalCents,
      delivery_fee_cents: deliveryFeeCents,
      discount_cents: discountCents,
      tip_cents: tipCents,
      total_cents: subtotalCents - discountCents + deliveryFeeCents + tipCents,
      distance_km: distanceKm === null ? null : Math.round(distanceKm * 100) / 100,
      eta_minutes: etaMinutes,
      promo_code: promo?.code ?? null,
    },
    promo,
    lineItems,
    trackedProductIds: new Set(products.filter((p) => p.stock_quantity != null).map((p) => p.id)),
  };
}

/** Checkout price preview — no rows written. */
export async function quoteOrder(params: OrderPricingParams): Promise<OrderQuote> {
  const { quote } = await priceOrder(params);
  return quote;
}

/**
 * Best-effort compensation for multi-row failures (no cross-table
 * transactions through PostgREST): re-adds whatever was decremented.
 */
async function restoreStock(lineItems: Array<{ product_id: string; quantity: number }>): Promise<void> {
  for (const li of lineItems) {
    // No-op (null) for untracked products — adjust_stock guards on that.
    await supabaseAdmin.rpc('adjust_stock', { p_product_id: li.product_id, p_delta: li.quantity });
  }
}

export async function createOrder(params: OrderPricingParams & {
  customerId: string;
  deliveryAddress?: string;
  scheduledFor?: string;
}): Promise<Order> {
  const { quote, promo, lineItems, trackedProductIds } = await priceOrder(params);

  // Reserve inventory before creating the order. adjust_stock is a single
  // conditional UPDATE, so two concurrent checkouts can't both take the last
  // unit; a null result means someone else got there first.
  const decremented: Array<{ product_id: string; quantity: number }> = [];
  for (const li of lineItems) {
    if (!trackedProductIds.has(li.product_id)) continue;
    const { data: adjusted, error } = await supabaseAdmin.rpc('adjust_stock', {
      p_product_id: li.product_id,
      p_delta: -li.quantity,
    });
    if (error || !adjusted) {
      await restoreStock(decremented);
      throw new HttpError(422, `${li.name} just sold out`);
    }
    decremented.push({ product_id: li.product_id, quantity: li.quantity });
  }

  const { data: order, error } = await supabaseAdmin
    .from('orders')
    .insert({
      customer_id: params.customerId,
      vendor_id: params.vendorId,
      status: 'pending_payment',
      subtotal_cents: quote.subtotal_cents,
      delivery_fee_cents: quote.delivery_fee_cents,
      tip_cents: quote.tip_cents,
      discount_cents: quote.discount_cents,
      promo_code: quote.promo_code,
      total_cents: quote.total_cents,
      eta_minutes: quote.eta_minutes,
      scheduled_for: params.scheduledFor ?? null,
      delivery_address: params.deliveryAddress ?? null,
      delivery_lat: params.deliveryLat ?? null,
      delivery_lng: params.deliveryLng ?? null,
    })
    .select()
    .single();

  if (error || !order) {
    await restoreStock(decremented);
    throw new HttpError(400, error?.message ?? 'Failed to create order');
  }

  const { error: itemsError } = await supabaseAdmin
    .from('order_items')
    .insert(lineItems.map((li) => ({ ...li, order_id: order.id })));

  if (itemsError) {
    await supabaseAdmin.from('orders').delete().eq('id', order.id);
    await restoreStock(decremented);
    throw new HttpError(400, itemsError.message);
  }

  await supabaseAdmin
    .from('deliveries')
    .insert({ order_id: order.id, status: 'unassigned', distance_km: quote.distance_km });

  if (promo) {
    await pricing.recordPromoRedemption(promo);
  }

  return order as Order;
}

export async function getOrderById(orderId: string): Promise<Order> {
  const { data, error } = await supabaseAdmin.from('orders').select('*').eq('id', orderId).single();
  if (error || !data) {
    throw new HttpError(404, 'Order not found');
  }
  return data as Order;
}

export async function listOrdersForCustomer(customerId: string): Promise<Order[]> {
  const { data, error } = await supabaseAdmin
    .from('orders')
    .select('*')
    .eq('customer_id', customerId)
    .order('created_at', { ascending: false });

  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []) as Order[];
}

export async function listOrdersForCourier(courierId: string): Promise<Order[]> {
  const { data, error } = await supabaseAdmin
    .from('orders')
    .select('*')
    .eq('courier_id', courierId)
    .order('created_at', { ascending: false });

  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []) as Order[];
}

const ALLOWED_TRANSITIONS: Record<OrderStatus, OrderStatus[]> = {
  pending_payment: ['paid', 'cancelled'],
  paid: ['accepted', 'cancelled'],
  accepted: ['preparing', 'cancelled'],
  preparing: ['ready_for_pickup', 'cancelled'],
  ready_for_pickup: ['courier_assigned', 'cancelled'],
  courier_assigned: ['picked_up', 'cancelled'],
  picked_up: ['in_transit'],
  in_transit: ['delivered'],
  delivered: [],
  cancelled: [],
};

export async function updateOrderStatus(orderId: string, nextStatus: OrderStatus): Promise<Order> {
  const current = await getOrderById(orderId);

  if (!ALLOWED_TRANSITIONS[current.status].includes(nextStatus)) {
    throw new HttpError(422, `Cannot transition order from ${current.status} to ${nextStatus}`);
  }

  const { data, error } = await supabaseAdmin
    .from('orders')
    .update({ status: nextStatus, updated_at: new Date().toISOString() })
    .eq('id', orderId)
    .select()
    .single();

  if (error || !data) {
    throw new HttpError(400, error?.message ?? 'Failed to update order status');
  }

  const order = data as Order;
  await applyStatusSideEffects(order);
  return order;
}

/**
 * Everything that should happen *because* an order changed status, kept out
 * of the transition itself so a failing side effect can't corrupt the state
 * machine.
 */
async function applyStatusSideEffects(order: Order): Promise<void> {
  try {
    switch (order.status) {
      case 'ready_for_pickup': {
        // Fire-and-forget: dispatch can take a few round trips and the vendor
        // tapping "ready" shouldn't wait on it. Self-claim stays available if
        // this finds nobody.
        void dispatchService.autoAssignCourier(order).catch((err: unknown) =>
          console.error(`[dispatch] auto-assign failed for order ${order.id}:`, err)
        );
        break;
      }
      case 'delivered': {
        await supabaseAdmin
          .from('deliveries')
          .update({ status: 'delivered', delivered_at: new Date().toISOString() })
          .eq('order_id', order.id);

        await payoutsService.releaseFundsForOrder(order.id);

        if (order.courier_id) {
          await dispatchService.releaseCourier(order.courier_id);
        }
        break;
      }
      case 'cancelled': {
        // Return reserved inventory to the shelf.
        const { data: items } = await supabaseAdmin
          .from('order_items')
          .select('*')
          .eq('order_id', order.id);
        await restoreStock(
          ((items ?? []) as Array<{ product_id: string; quantity: number }>).map((li) => ({
            product_id: li.product_id,
            quantity: li.quantity,
          }))
        );
        if (order.courier_id) {
          await dispatchService.releaseCourier(order.courier_id);
        }
        break;
      }
      default:
        break;
    }
  } catch (err) {
    // The status change itself is committed; log and move on.
    console.error(`[orders] side effects failed for order ${order.id} (${order.status}):`, err);
  }

  void notificationsService.notifyOrderStatus(order).catch((err: unknown) =>
    console.error(`[orders] notifications failed for order ${order.id}:`, err)
  );
}

export async function assignCourier(orderId: string, courierId: string): Promise<Order> {
  // Conditional update doubles as the lock: two couriers racing to claim
  // the same order can't both match status='ready_for_pickup' AND
  // courier_id IS NULL — exactly one update wins, the other gets 0 rows.
  const { data, error } = await supabaseAdmin
    .from('orders')
    .update({
      courier_id: courierId,
      status: 'courier_assigned',
      updated_at: new Date().toISOString(),
    })
    .eq('id', orderId)
    .eq('status', 'ready_for_pickup')
    .is('courier_id', null)
    .select()
    .maybeSingle();

  if (error) {
    throw new HttpError(400, error.message);
  }
  if (!data) {
    throw new HttpError(409, 'Order is no longer available to claim');
  }

  await supabaseAdmin
    .from('deliveries')
    .update({ courier_id: courierId, status: 'assigned', assigned_at: new Date().toISOString() })
    .eq('order_id', orderId);

  const assigned = data as Order;
  void notificationsService.notifyOrderStatus(assigned).catch((err: unknown) =>
    console.error(`[orders] notifications failed for order ${assigned.id}:`, err)
  );
  return assigned;
}

// Once a courier has physically picked the order up, only vendor-side
// re-routing logic (out of scope here) should cancel it — a customer or
// vendor tapping "cancel" mid-transit isn't a supported flow.
const CUSTOMER_CANCELLABLE_STATUSES = new Set<OrderStatus>(['pending_payment', 'paid', 'accepted', 'preparing']);
const VENDOR_CANCELLABLE_STATUSES = new Set<OrderStatus>(['paid', 'accepted', 'preparing', 'ready_for_pickup']);

export async function cancelOrder(orderId: string, actor: { id: string; role: UserRole }): Promise<Order> {
  const order = await getOrderById(orderId);

  if (actor.role === 'customer') {
    if (order.customer_id !== actor.id) {
      throw new HttpError(403, 'Not your order');
    }
    if (!CUSTOMER_CANCELLABLE_STATUSES.has(order.status)) {
      throw new HttpError(422, `Cannot cancel an order in status ${order.status}`);
    }
  } else if (actor.role === 'vendor') {
    const vendor = await getVendorByOwner(actor.id);
    if (!vendor || vendor.id !== order.vendor_id) {
      throw new HttpError(403, 'Not your order');
    }
    if (!VENDOR_CANCELLABLE_STATUSES.has(order.status)) {
      throw new HttpError(422, `Cannot cancel an order in status ${order.status}`);
    }
  } else {
    throw new HttpError(403, 'Only the customer or vendor can cancel this order');
  }

  return updateOrderStatus(orderId, 'cancelled');
}
