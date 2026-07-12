import { fakeSupabase } from './fakeSupabase';

jest.mock('../src/config/supabaseClient', () => ({
  supabaseAdmin: fakeSupabase,
}));

import * as dispatchService from '../src/services/dispatch.service';
import type { Order } from '../src/types/domain';

async function seedCourier(id: string, overrides: Record<string, unknown> = {}) {
  await fakeSupabase.from('users').insert({
    id,
    role: 'courier',
    is_available: true,
    last_lat: 31.5,
    last_lng: 74.35,
    last_seen_at: new Date().toISOString(),
    ...overrides,
  });
}

async function seedReadyOrder(): Promise<Order> {
  const { data } = await fakeSupabase
    .from('orders')
    .insert({
      customer_id: 'cust-1',
      vendor_id: 'vendor-1',
      status: 'ready_for_pickup',
      courier_id: null,
      total_cents: 1000,
    })
    .select()
    .single();
  const order = data as unknown as Order;
  await fakeSupabase.from('deliveries').insert({ order_id: order.id, status: 'unassigned' });
  return order;
}

describe('dispatch service', () => {
  beforeEach(async () => {
    fakeSupabase.reset();
    // Vendor pickup point at (31.5, 74.35).
    await fakeSupabase.from('vendors').insert({
      id: 'vendor-1',
      owner_user_id: 'vendor-owner-1',
      is_active: true,
      approval_status: 'approved',
      lat: 31.5,
      lng: 74.35,
    });
  });

  it('assigns the nearest available courier and takes them off the pool', async () => {
    await seedCourier('courier-near', { last_lat: 31.51, last_lng: 74.35 });
    await seedCourier('courier-far', { last_lat: 32.5, last_lng: 74.35 });
    const order = await seedReadyOrder();

    const assigned = await dispatchService.autoAssignCourier(order);

    expect(assigned?.courier_id).toBe('courier-near');
    expect(assigned?.status).toBe('courier_assigned');

    const { data: courier } = await fakeSupabase.from('users').select('*').eq('id', 'courier-near').single();
    expect((courier as { is_available: boolean }).is_available).toBe(false);
  });

  it('ignores couriers with stale location reports', async () => {
    await seedCourier('courier-stale', {
      last_seen_at: new Date(Date.now() - 60 * 60 * 1000).toISOString(),
    });
    const order = await seedReadyOrder();

    expect(await dispatchService.autoAssignCourier(order)).toBeNull();
  });

  it('ignores couriers who are mid-delivery even if flagged available', async () => {
    await seedCourier('courier-busy');
    await fakeSupabase.from('orders').insert({
      customer_id: 'cust-9',
      vendor_id: 'vendor-1',
      status: 'in_transit',
      courier_id: 'courier-busy',
      total_cents: 500,
    });
    const order = await seedReadyOrder();

    expect(await dispatchService.autoAssignCourier(order)).toBeNull();
  });

  it('returns null when the vendor has no coordinates', async () => {
    await fakeSupabase.from('vendors').update({ lat: null, lng: null }).eq('id', 'vendor-1');
    await seedCourier('courier-1');
    const order = await seedReadyOrder();

    expect(await dispatchService.autoAssignCourier(order)).toBeNull();
  });

  it('releaseCourier puts a courier back into the pool', async () => {
    await seedCourier('courier-1', { is_available: false });
    await dispatchService.releaseCourier('courier-1');

    const { data } = await fakeSupabase.from('users').select('*').eq('id', 'courier-1').single();
    expect((data as { is_available: boolean }).is_available).toBe(true);
  });
});
