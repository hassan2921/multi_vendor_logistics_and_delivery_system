import type { Request, Response } from 'express';
import { z } from 'zod';
import { HttpError } from '../middleware/errorHandler.middleware';
import * as addressesService from '../services/addresses.service';

export async function listMine(req: Request, res: Response) {
  const addresses = await addressesService.listAddresses(req.authUser!.id);
  res.json({ addresses });
}

const createAddressSchema = z.object({
  label: z.string().min(1).max(50),
  addressLine: z.string().min(1),
  lat: z.number().optional(),
  lng: z.number().optional(),
  isDefault: z.boolean().optional(),
});

export async function create(req: Request, res: Response) {
  const parsed = createAddressSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }
  const address = await addressesService.createAddress(req.authUser!.id, parsed.data);
  res.status(201).json({ address });
}

const updateAddressSchema = z.object({
  label: z.string().min(1).max(50).optional(),
  addressLine: z.string().min(1).optional(),
  lat: z.number().nullable().optional(),
  lng: z.number().nullable().optional(),
  isDefault: z.boolean().optional(),
});

export async function update(req: Request, res: Response) {
  const parsed = updateAddressSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }
  const address = await addressesService.updateAddress(req.authUser!.id, req.params.id, parsed.data);
  res.json({ address });
}

export async function remove(req: Request, res: Response) {
  await addressesService.deleteAddress(req.authUser!.id, req.params.id);
  res.status(204).end();
}
