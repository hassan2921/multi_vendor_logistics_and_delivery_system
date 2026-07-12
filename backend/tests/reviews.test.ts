import { fakeSupabase } from './fakeSupabase';

jest.mock('../src/config/supabaseClient', () => ({
  supabaseAdmin: fakeSupabase,
}));

import * as reviewsService from '../src/services/reviews.service';

async function seedDeliveredOrder(id: string, customerId = 'cust-1') {
  await fakeSupabase.from('orders').insert({
    id,
    customer_id: customerId,
    vendor_id: 'vendor-1',
    status: 'delivered',
    total_cents: 1000,
  });
}

describe('reviews service', () => {
  beforeEach(async () => {
    fakeSupabase.reset();
    await fakeSupabase.from('vendors').insert({
      id: 'vendor-1',
      owner_user_id: 'vendor-owner-1',
      rating_avg: 0,
      rating_count: 0,
    });
  });

  it('lets the customer review their delivered order and updates the vendor aggregate', async () => {
    await seedDeliveredOrder('order-1');

    const review = await reviewsService.createReview({
      orderId: 'order-1',
      customerId: 'cust-1',
      rating: 4,
      comment: 'Quick delivery',
    });
    expect(review.rating).toBe(4);

    const { data: vendor } = await fakeSupabase.from('vendors').select('*').eq('id', 'vendor-1').single();
    expect(vendor).toMatchObject({ rating_avg: 4, rating_count: 1 });
  });

  it('averages across multiple reviews', async () => {
    await seedDeliveredOrder('order-1');
    await seedDeliveredOrder('order-2');

    await reviewsService.createReview({ orderId: 'order-1', customerId: 'cust-1', rating: 5 });
    await reviewsService.createReview({ orderId: 'order-2', customerId: 'cust-1', rating: 2 });

    const { data: vendor } = await fakeSupabase.from('vendors').select('*').eq('id', 'vendor-1').single();
    expect(vendor).toMatchObject({ rating_avg: 3.5, rating_count: 2 });
  });

  it('rejects reviewing someone else\'s order', async () => {
    await seedDeliveredOrder('order-1', 'cust-2');

    await expect(
      reviewsService.createReview({ orderId: 'order-1', customerId: 'cust-1', rating: 5 })
    ).rejects.toMatchObject({ status: 403 });
  });

  it('rejects reviewing an undelivered order', async () => {
    await fakeSupabase.from('orders').insert({
      id: 'order-1',
      customer_id: 'cust-1',
      vendor_id: 'vendor-1',
      status: 'in_transit',
      total_cents: 1000,
    });

    await expect(
      reviewsService.createReview({ orderId: 'order-1', customerId: 'cust-1', rating: 5 })
    ).rejects.toMatchObject({ status: 422 });
  });

  it('rejects a second review of the same order', async () => {
    await seedDeliveredOrder('order-1');
    await reviewsService.createReview({ orderId: 'order-1', customerId: 'cust-1', rating: 5 });

    await expect(
      reviewsService.createReview({ orderId: 'order-1', customerId: 'cust-1', rating: 1 })
    ).rejects.toMatchObject({ status: 409 });
  });
});
