import type { Request, Response } from 'express';
import { z } from 'zod';
import { HttpError } from '../middleware/errorHandler.middleware';
import * as ordersService from '../services/orders.service';
import * as stripeService from '../services/stripe.service';
import * as vendorsService from '../services/vendors.service';
import type { Order } from '../types/domain';

const createOrderSchema = z.object({
  vendorId: z.string().uuid(),
  items: z
    .array(
      z.object({
        productId: z.string().uuid(),
        quantity: z.number().int().positive(),
      })
    )
    .min(1),
  deliveryAddress: z.string().optional(),
  deliveryLat: z.number().optional(),
  deliveryLng: z.number().optional(),
});

export async function createOrder(req: Request, res: Response) {
  const parsed = createOrderSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }
  if (req.authUser?.role !== 'customer') {
    throw new HttpError(403, 'Only customers can create orders');
  }

  const order = await ordersService.createOrder({
    customerId: req.authUser.id,
    vendorId: parsed.data.vendorId,
    items: parsed.data.items,
    deliveryAddress: parsed.data.deliveryAddress,
    deliveryLat: parsed.data.deliveryLat,
    deliveryLng: parsed.data.deliveryLng,
  });

  res.status(201).json({ order });
}

async function assertCanViewOrder(order: Order, authUser: NonNullable<Request['authUser']>) {
  if (authUser.role === 'customer' && order.customer_id === authUser.id) return;
  if (authUser.role === 'courier' && order.courier_id === authUser.id) return;
  if (authUser.role === 'vendor') {
    const vendor = await vendorsService.getVendorByOwner(authUser.id);
    if (vendor && vendor.id === order.vendor_id) return;
  }
  throw new HttpError(403, 'You do not have access to this order');
}

export async function getOrder(req: Request, res: Response) {
  const order = await ordersService.getOrderById(req.params.id);
  await assertCanViewOrder(order, req.authUser!);
  res.json({ order });
}

const updateStatusSchema = z.object({
  status: z.enum([
    'pending_payment',
    'paid',
    'accepted',
    'preparing',
    'ready_for_pickup',
    'courier_assigned',
    'picked_up',
    'in_transit',
    'delivered',
    'cancelled',
  ]),
});

export async function updateStatus(req: Request, res: Response) {
  const parsed = updateStatusSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }

  const order = await ordersService.updateOrderStatus(req.params.id, parsed.data.status);
  res.json({ order });
}

export async function claimDelivery(req: Request, res: Response) {
  if (req.authUser?.role !== 'courier') {
    throw new HttpError(403, 'Only couriers can claim deliveries');
  }
  const order = await ordersService.assignCourier(req.params.id, req.authUser.id);
  res.json({ order });
}

export async function cancelOrder(req: Request, res: Response) {
  const authUser = req.authUser!;
  const order = await ordersService.cancelOrder(req.params.id, { id: authUser.id, role: authUser.role });
  // Refunds only actually fire if the order had a captured payment.
  await stripeService.refundIfPaid(order.id);
  res.json({ order });
}

export async function listMine(req: Request, res: Response) {
  const authUser = req.authUser!;

  if (authUser.role === 'customer') {
    return res.json({ orders: await ordersService.listOrdersForCustomer(authUser.id) });
  }
  if (authUser.role === 'courier') {
    return res.json({ orders: await ordersService.listOrdersForCourier(authUser.id) });
  }

  const vendor = await vendorsService.getVendorByOwner(authUser.id);
  if (!vendor) {
    return res.json({ orders: [] });
  }
  res.json({ orders: await vendorsService.listOrdersForVendor(vendor.id) });
}
