import type { Request, Response } from 'express';
import { z } from 'zod';
import { HttpError } from '../middleware/errorHandler.middleware';
import * as ordersService from '../services/orders.service';

const createOrderSchema = z.object({
  vendorId: z.string().uuid(),
  items: z
    .array(
      z.object({
        name: z.string().min(1),
        quantity: z.number().int().positive(),
        unit_price_cents: z.number().int().nonnegative(),
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

export async function getOrder(req: Request, res: Response) {
  const order = await ordersService.getOrderById(req.params.id);
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
