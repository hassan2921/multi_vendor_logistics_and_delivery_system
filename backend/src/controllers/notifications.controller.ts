import type { Request, Response } from 'express';
import { z } from 'zod';
import { supabaseAdmin } from '../config/supabaseClient';
import { HttpError } from '../middleware/errorHandler.middleware';
import * as notificationsService from '../services/notifications.service';

const registerTokenSchema = z.object({
  token: z.string().min(1),
  platform: z.enum(['android', 'ios', 'web']).optional(),
});

export async function registerDeviceToken(req: Request, res: Response) {
  const parsed = registerTokenSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }

  await notificationsService.registerDeviceToken(req.authUser!.id, parsed.data.token, parsed.data.platform);
  res.status(204).end();
}

export async function listMine(req: Request, res: Response) {
  const { data, error } = await supabaseAdmin
    .from('notifications')
    .select('*')
    .eq('user_id', req.authUser!.id)
    .order('created_at', { ascending: false })
    .limit(50);

  if (error) {
    throw new HttpError(500, error.message);
  }
  res.json({ notifications: data ?? [] });
}

export async function markRead(req: Request, res: Response) {
  const { error } = await supabaseAdmin
    .from('notifications')
    .update({ read: true })
    .eq('id', req.params.id)
    .eq('user_id', req.authUser!.id);

  if (error) {
    throw new HttpError(400, error.message);
  }
  res.status(204).end();
}
