import type { Request, Response } from 'express';
import { z } from 'zod';
import { HttpError } from '../middleware/errorHandler.middleware';
import * as dispatchService from '../services/dispatch.service';
import * as payoutsService from '../services/payouts.service';

const availabilitySchema = z.object({
  isAvailable: z.boolean(),
  lat: z.number().optional(),
  lng: z.number().optional(),
});

export async function setAvailability(req: Request, res: Response) {
  const parsed = availabilitySchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }

  await dispatchService.setCourierAvailability(req.authUser!.id, parsed.data);
  res.json({ isAvailable: parsed.data.isAvailable });
}

export async function getEarnings(req: Request, res: Response) {
  const earnings = await payoutsService.getCourierEarnings(req.authUser!.id);
  res.json({ earnings });
}
