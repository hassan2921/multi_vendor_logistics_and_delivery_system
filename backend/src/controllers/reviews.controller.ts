import type { Request, Response } from 'express';
import { z } from 'zod';
import { HttpError } from '../middleware/errorHandler.middleware';
import * as reviewsService from '../services/reviews.service';

const createReviewSchema = z.object({
  rating: z.number().int().min(1).max(5),
  comment: z.string().max(2000).optional(),
});

export async function createReview(req: Request, res: Response) {
  if (req.authUser?.role !== 'customer') {
    throw new HttpError(403, 'Only customers can leave reviews');
  }
  const parsed = createReviewSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }

  const review = await reviewsService.createReview({
    orderId: req.params.id,
    customerId: req.authUser.id,
    rating: parsed.data.rating,
    comment: parsed.data.comment,
  });
  res.status(201).json({ review });
}

export async function listVendorReviews(req: Request, res: Response) {
  const reviews = await reviewsService.listReviewsForVendor(req.params.vendorId);
  res.json({ reviews });
}
