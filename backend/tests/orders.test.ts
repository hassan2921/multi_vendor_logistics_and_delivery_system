import { fakeSupabase } from './fakeSupabase';

jest.mock('../src/config/supabaseClient', () => ({
  supabaseAdmin: fakeSupabase,
}));

import * as ordersService from '../src/services/orders.service';

describe('orders service', () => {
  beforeEach(() => {
    fakeSupabase.reset();
  });

  it('creates an order with a total computed from its line items', async () => {
    const order = await ordersService.createOrder({
      customerId: 'cust-1',
      vendorId: 'vendor-1',
      items: [
        { name: 'Widget', quantity: 2, unit_price_cents: 500 },
        { name: 'Gadget', quantity: 1, unit_price_cents: 250 },
      ],
    });

    expect(order.total_cents).toBe(1250);
    expect(order.status).toBe('pending_payment');
  });

  it('allows a valid status transition', async () => {
    const order = await ordersService.createOrder({
      customerId: 'cust-1',
      vendorId: 'vendor-1',
      items: [{ name: 'Widget', quantity: 1, unit_price_cents: 100 }],
    });

    const paid = await ordersService.updateOrderStatus(order.id, 'paid');
    expect(paid.status).toBe('paid');
  });

  it('rejects an invalid status transition', async () => {
    const order = await ordersService.createOrder({
      customerId: 'cust-1',
      vendorId: 'vendor-1',
      items: [{ name: 'Widget', quantity: 1, unit_price_cents: 100 }],
    });

    // pending_payment -> delivered is not a legal jump
    await expect(ordersService.updateOrderStatus(order.id, 'delivered')).rejects.toThrow();
  });
});
