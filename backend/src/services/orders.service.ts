import { supabaseAdmin } from '../config/supabaseClient';
import type { Order, OrderItemSelection, OrderStatus, UserRole } from '../types/domain';
import { HttpError } from '../middleware/errorHandler.middleware';
import { getProductsByIds, getVendorByOwner } from './vendors.service';

export async function createOrder(params: {
  customerId: string;
  vendorId: string;
  items: OrderItemSelection[];
  deliveryAddress?: string;
  deliveryLat?: number;
  deliveryLng?: number;
}): Promise<Order> {
  if (params.items.length === 0) {
    throw new HttpError(400, 'Order must contain at least one item');
  }

  // Priced entirely from the catalog — the client only ever sends product
  // ids and quantities, never a price, so a tampered client can't discount
  // its own order.
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
    return {
      product_id: product.id,
      name: product.name,
      quantity: item.quantity,
      unit_price_cents: product.price_cents,
    };
  });

  const totalCents = lineItems.reduce((sum, li) => sum + li.quantity * li.unit_price_cents, 0);

  const { data: order, error } = await supabaseAdmin
    .from('orders')
    .insert({
      customer_id: params.customerId,
      vendor_id: params.vendorId,
      status: 'pending_payment',
      total_cents: totalCents,
      delivery_address: params.deliveryAddress ?? null,
      delivery_lat: params.deliveryLat ?? null,
      delivery_lng: params.deliveryLng ?? null,
    })
    .select()
    .single();

  if (error || !order) {
    throw new HttpError(400, error?.message ?? 'Failed to create order');
  }

  const { error: itemsError } = await supabaseAdmin
    .from('order_items')
    .insert(lineItems.map((li) => ({ ...li, order_id: order.id })));

  if (itemsError) {
    await supabaseAdmin.from('orders').delete().eq('id', order.id);
    throw new HttpError(400, itemsError.message);
  }

  await supabaseAdmin.from('deliveries').insert({ order_id: order.id, status: 'unassigned' });

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

  return data as Order;
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

  return data as Order;
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
