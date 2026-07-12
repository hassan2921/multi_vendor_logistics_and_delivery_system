import { supabaseAdmin } from '../config/supabaseClient';
import { HttpError } from '../middleware/errorHandler.middleware';
import type { Review } from '../types/domain';
import * as ordersService from './orders.service';

export async function createReview(params: {
  orderId: string;
  customerId: string;
  rating: number;
  comment?: string;
}): Promise<Review> {
  const order = await ordersService.getOrderById(params.orderId);

  if (order.customer_id !== params.customerId) {
    throw new HttpError(403, 'You can only review your own orders');
  }
  if (order.status !== 'delivered') {
    throw new HttpError(422, 'You can only review delivered orders');
  }

  const { data, error } = await supabaseAdmin
    .from('reviews')
    .insert({
      order_id: order.id,
      vendor_id: order.vendor_id,
      customer_id: params.customerId,
      rating: params.rating,
      comment: params.comment ?? null,
    })
    .select()
    .single();

  if (error || !data) {
    // Unique constraint on order_id: one review per order.
    if (error?.message.includes('duplicate') || error?.message.includes('unique')) {
      throw new HttpError(409, 'This order has already been reviewed');
    }
    throw new HttpError(400, error?.message ?? 'Failed to create review');
  }

  await recomputeVendorRating(order.vendor_id);
  return data as Review;
}

/**
 * Denormalized aggregate on the vendor row so storefront lists can sort and
 * filter by rating without a join. Recomputed from scratch on every new
 * review — correct under concurrency (last write recomputes everything).
 */
async function recomputeVendorRating(vendorId: string): Promise<void> {
  const { data } = await supabaseAdmin.from('reviews').select('*').eq('vendor_id', vendorId);
  const reviews = (data ?? []) as Review[];
  if (reviews.length === 0) return;

  const avg = reviews.reduce((sum, r) => sum + r.rating, 0) / reviews.length;
  await supabaseAdmin
    .from('vendors')
    .update({ rating_avg: Math.round(avg * 100) / 100, rating_count: reviews.length })
    .eq('id', vendorId);
}

export async function listReviewsForVendor(vendorId: string): Promise<Review[]> {
  const { data, error } = await supabaseAdmin
    .from('reviews')
    .select('*')
    .eq('vendor_id', vendorId)
    .order('created_at', { ascending: false });

  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []) as Review[];
}
