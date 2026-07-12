import type { Request, Response } from 'express';
import { z } from 'zod';
import { HttpError } from '../middleware/errorHandler.middleware';
import * as stripeService from '../services/stripe.service';

const createIntentSchema = z.object({
  orderId: z.string().uuid(),
});

export async function createIntent(req: Request, res: Response) {
  const parsed = createIntentSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }

  if (req.authUser?.role !== 'customer') {
    throw new HttpError(403, 'Only customers can pay for orders');
  }
  const { clientSecret } = await stripeService.createPaymentIntent(parsed.data.orderId, req.authUser.id);
  res.status(201).json({ clientSecret });
}

export async function webhook(req: Request, res: Response) {
  const signature = req.header('stripe-signature');
  if (!signature) {
    throw new HttpError(400, 'Missing stripe-signature header');
  }

  let event;
  try {
    // req.body is the raw Buffer here because this route is mounted with
    // express.raw(), not the global JSON parser — required for signature verification.
    event = stripeService.verifyWebhookSignature(req.body as Buffer, signature);
  } catch (err) {
    throw new HttpError(400, `Webhook signature verification failed: ${(err as Error).message}`);
  }

  await stripeService.handleWebhookEvent(event);
  res.json({ received: true });
}
