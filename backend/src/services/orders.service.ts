import { supabaseAdmin } from '../config/supabaseClient';
import type { Order, OrderItemInput, OrderStatus } from '../types/domain';
import { HttpError } from '../middleware/errorHandler.middleware';

export async function createOrder(params: {
  customerId: string;
  vendorId: string;
  items: OrderItemInput[];
  deliveryAddress?: string;
  deliveryLat?: number;
  deliveryLng?: number;
}): Promise<Order> {
  const totalCents = params.items.reduce((sum, item) => sum + item.quantity * item.unit_price_cents, 0);

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

  const { error: itemsError } = await supabaseAdmin.from('order_items').insert(
    params.items.map((item) => ({
      order_id: order.id,
      name: item.name,
      quantity: item.quantity,
      unit_price_cents: item.unit_price_cents,
    }))
  );

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
