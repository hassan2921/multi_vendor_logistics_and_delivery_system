import { fakeSupabase } from './fakeSupabase';

jest.mock('../src/config/supabaseClient', () => ({
  supabaseAdmin: fakeSupabase,
}));

import * as ordersService from '../src/services/orders.service';

async function seedProduct(overrides: Partial<{ id: string; vendor_id: string; price_cents: number; is_available: boolean; name: string }> = {}) {
  const { data } = await fakeSupabase
    .from('products')
    .insert({
      vendor_id: 'vendor-1',
      name: 'Widget',
      price_cents: 500,
      is_available: true,
      ...overrides,
    })
    .select()
    .single();
  return data as { id: string };
}

describe('orders service', () => {
  beforeEach(() => {
    fakeSupabase.reset();
  });

  it('prices an order from the product catalog, not from client input', async () => {
    const widget = await seedProduct({ price_cents: 500 });
    const gadget = await seedProduct({ name: 'Gadget', price_cents: 250 });

    const order = await ordersService.createOrder({
      customerId: 'cust-1',
      vendorId: 'vendor-1',
      items: [
        { productId: widget.id, quantity: 2 },
        { productId: gadget.id, quantity: 1 },
      ],
    });

    expect(order.total_cents).toBe(1250);
    expect(order.status).toBe('pending_payment');
  });

  it('ignores any attempt to smuggle a price through and always uses the DB price', async () => {
    const product = await seedProduct({ price_cents: 500 });

    const order = await ordersService.createOrder({
      customerId: 'cust-1',
      vendorId: 'vendor-1',
      // @ts-expect-error deliberately passing an extra field a tampered client might send
      items: [{ productId: product.id, quantity: 1, unit_price_cents: 1 }],
    });

    expect(order.total_cents).toBe(500);
  });

  it('rejects an order referencing a product from a different vendor', async () => {
    const product = await seedProduct({ vendor_id: 'vendor-2' });

    await expect(
      ordersService.createOrder({
        customerId: 'cust-1',
        vendorId: 'vendor-1',
        items: [{ productId: product.id, quantity: 1 }],
      })
    ).rejects.toMatchObject({ status: 422 });
  });

  it('rejects an order for an unavailable product', async () => {
    const product = await seedProduct({ is_available: false });

    await expect(
      ordersService.createOrder({
        customerId: 'cust-1',
        vendorId: 'vendor-1',
        items: [{ productId: product.id, quantity: 1 }],
      })
    ).rejects.toMatchObject({ status: 422 });
  });

  it('allows a valid status transition', async () => {
    const product = await seedProduct();
    const order = await ordersService.createOrder({
      customerId: 'cust-1',
      vendorId: 'vendor-1',
      items: [{ productId: product.id, quantity: 1 }],
    });

    const paid = await ordersService.updateOrderStatus(order.id, 'paid');
    expect(paid.status).toBe('paid');
  });

  it('rejects an invalid status transition', async () => {
    const product = await seedProduct();
    const order = await ordersService.createOrder({
      customerId: 'cust-1',
      vendorId: 'vendor-1',
      items: [{ productId: product.id, quantity: 1 }],
    });

    // pending_payment -> delivered is not a legal jump
    await expect(ordersService.updateOrderStatus(order.id, 'delivered')).rejects.toThrow();
  });

  it('lets exactly one courier claim an order; the loser gets a 409', async () => {
    const product = await seedProduct();
    const order = await ordersService.createOrder({
      customerId: 'cust-1',
      vendorId: 'vendor-1',
      items: [{ productId: product.id, quantity: 1 }],
    });
    await fakeSupabase.from('orders').update({ status: 'ready_for_pickup' }).eq('id', order.id);

    const claimed = await ordersService.assignCourier(order.id, 'courier-1');
    expect(claimed.courier_id).toBe('courier-1');
    expect(claimed.status).toBe('courier_assigned');

    await expect(ordersService.assignCourier(order.id, 'courier-2')).rejects.toMatchObject({
      status: 409,
    });
  });

  describe('cancelOrder', () => {
    it('lets the owning customer cancel a not-yet-picked-up order', async () => {
      const product = await seedProduct();
      const order = await ordersService.createOrder({
        customerId: 'cust-1',
        vendorId: 'vendor-1',
        items: [{ productId: product.id, quantity: 1 }],
      });

      const cancelled = await ordersService.cancelOrder(order.id, { id: 'cust-1', role: 'customer' });
      expect(cancelled.status).toBe('cancelled');
    });

    it('rejects a different customer trying to cancel someone else\'s order', async () => {
      const product = await seedProduct();
      const order = await ordersService.createOrder({
        customerId: 'cust-1',
        vendorId: 'vendor-1',
        items: [{ productId: product.id, quantity: 1 }],
      });

      await expect(
        ordersService.cancelOrder(order.id, { id: 'cust-2', role: 'customer' })
      ).rejects.toMatchObject({ status: 403 });
    });

    it('lets the owning vendor cancel, but rejects an unrelated vendor', async () => {
      const product = await seedProduct();
      const order = await ordersService.createOrder({
        customerId: 'cust-1',
        vendorId: 'vendor-1',
        items: [{ productId: product.id, quantity: 1 }],
      });
      await fakeSupabase.from('orders').update({ status: 'paid' }).eq('id', order.id);

      await expect(
        ordersService.cancelOrder(order.id, { id: 'not-the-owner', role: 'vendor' })
      ).rejects.toMatchObject({ status: 403 });

      await fakeSupabase.from('vendors').insert({ id: 'vendor-1', owner_user_id: 'vendor-owner-1' });
      const cancelled = await ordersService.cancelOrder(order.id, { id: 'vendor-owner-1', role: 'vendor' });
      expect(cancelled.status).toBe('cancelled');
    });

    it('refuses to cancel an order that has already been picked up', async () => {
      const product = await seedProduct();
      const order = await ordersService.createOrder({
        customerId: 'cust-1',
        vendorId: 'vendor-1',
        items: [{ productId: product.id, quantity: 1 }],
      });
      await fakeSupabase.from('orders').update({ status: 'ready_for_pickup' }).eq('id', order.id);
      await ordersService.assignCourier(order.id, 'courier-1');
      await fakeSupabase.from('orders').update({ status: 'picked_up' }).eq('id', order.id);

      await expect(
        ordersService.cancelOrder(order.id, { id: 'cust-1', role: 'customer' })
      ).rejects.toMatchObject({ status: 422 });
    });
  });

  describe('order history', () => {
    it('lists a customer\'s own orders, newest first', async () => {
      const product = await seedProduct();
      const first = await ordersService.createOrder({
        customerId: 'cust-1',
        vendorId: 'vendor-1',
        items: [{ productId: product.id, quantity: 1 }],
      });
      const second = await ordersService.createOrder({
        customerId: 'cust-1',
        vendorId: 'vendor-1',
        items: [{ productId: product.id, quantity: 1 }],
      });
      await ordersService.createOrder({
        customerId: 'cust-2',
        vendorId: 'vendor-1',
        items: [{ productId: product.id, quantity: 1 }],
      });

      const mine = await ordersService.listOrdersForCustomer('cust-1');
      expect(mine.map((o) => o.id).sort()).toEqual([first.id, second.id].sort());
    });

    it('lists a courier\'s claimed deliveries', async () => {
      const product = await seedProduct();
      const order = await ordersService.createOrder({
        customerId: 'cust-1',
        vendorId: 'vendor-1',
        items: [{ productId: product.id, quantity: 1 }],
      });
      await fakeSupabase.from('orders').update({ status: 'ready_for_pickup' }).eq('id', order.id);
      await ordersService.assignCourier(order.id, 'courier-1');

      const mine = await ordersService.listOrdersForCourier('courier-1');
      expect(mine).toHaveLength(1);
      expect(mine[0].id).toBe(order.id);
    });
  });
});
