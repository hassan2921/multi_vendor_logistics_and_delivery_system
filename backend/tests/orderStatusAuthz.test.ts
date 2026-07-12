import { fakeSupabase } from './fakeSupabase';

jest.mock('../src/config/supabaseClient', () => ({
  supabaseAdmin: fakeSupabase,
}));

import express from 'express';
import request from 'supertest';
import * as ordersController from '../src/controllers/orders.controller';
import { errorHandler } from '../src/middleware/errorHandler.middleware';
import { asyncHandler } from '../src/utils/asyncHandler';
import type { UserRole } from '../src/types/domain';

function appAs(user: { id: string; role: UserRole }) {
  const app = express();
  app.use(express.json());
  app.patch(
    '/orders/:id/status',
    (req, _res, next) => {
      req.authUser = { id: user.id, role: user.role } as NonNullable<typeof req.authUser>;
      next();
    },
    asyncHandler(ordersController.updateStatus)
  );
  app.use(errorHandler);
  return app;
}

describe('PATCH /orders/:id/status authorization', () => {
  beforeEach(async () => {
    fakeSupabase.reset();
    await fakeSupabase.from('vendors').insert([
      { id: 'vendor-1', owner_user_id: 'vendor-owner-1', is_active: true, approval_status: 'approved' },
      { id: 'vendor-2', owner_user_id: 'vendor-owner-2', is_active: true, approval_status: 'approved' },
    ]);
    await fakeSupabase.from('orders').insert({
      id: 'order-1',
      customer_id: 'cust-1',
      vendor_id: 'vendor-1',
      courier_id: 'courier-1',
      status: 'paid',
      total_cents: 1000,
      currency: 'usd',
    });
  });

  it("rejects a vendor updating another vendor's order", async () => {
    const res = await request(appAs({ id: 'vendor-owner-2', role: 'vendor' }))
      .patch('/orders/order-1/status')
      .send({ status: 'accepted' });
    expect(res.status).toBe(403);
  });

  it('lets the owning vendor accept their order', async () => {
    const res = await request(appAs({ id: 'vendor-owner-1', role: 'vendor' }))
      .patch('/orders/order-1/status')
      .send({ status: 'accepted' });
    expect(res.status).toBe(200);
    expect(res.body.order.status).toBe('accepted');
  });

  it("rejects a vendor forging the system-only 'paid' status", async () => {
    await fakeSupabase.from('orders').update({ status: 'pending_payment' }).eq('id', 'order-1');
    const res = await request(appAs({ id: 'vendor-owner-1', role: 'vendor' }))
      .patch('/orders/order-1/status')
      .send({ status: 'paid' });
    expect(res.status).toBe(403);
  });

  it('rejects a courier who is not assigned to the order', async () => {
    await fakeSupabase.from('orders').update({ status: 'courier_assigned' }).eq('id', 'order-1');
    const res = await request(appAs({ id: 'courier-OTHER', role: 'courier' }))
      .patch('/orders/order-1/status')
      .send({ status: 'picked_up' });
    expect(res.status).toBe(403);
  });

  it('lets the assigned courier mark the order picked up', async () => {
    await fakeSupabase.from('orders').update({ status: 'courier_assigned' }).eq('id', 'order-1');
    const res = await request(appAs({ id: 'courier-1', role: 'courier' }))
      .patch('/orders/order-1/status')
      .send({ status: 'picked_up' });
    expect(res.status).toBe(200);
    expect(res.body.order.status).toBe('picked_up');
  });

  it('rejects a courier setting vendor-side statuses', async () => {
    const res = await request(appAs({ id: 'courier-1', role: 'courier' }))
      .patch('/orders/order-1/status')
      .send({ status: 'accepted' });
    expect(res.status).toBe(403);
  });
});
