import type { Request, Response } from 'express';
import { z } from 'zod';
import { supabaseAdmin } from '../config/supabaseClient';
import { HttpError } from '../middleware/errorHandler.middleware';

const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  fullName: z.string().min(1),
  role: z.enum(['customer', 'courier', 'vendor']),
});

export async function register(req: Request, res: Response) {
  const parsed = registerSchema.safeParse(req.body);
  if (!parsed.success) {
    throw new HttpError(400, parsed.error.issues.map((i) => i.message).join(', '));
  }
  const { email, password, fullName, role } = parsed.data;

  const { data: created, error: createError } = await supabaseAdmin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });

  if (createError || !created.user) {
    throw new HttpError(400, createError?.message ?? 'Failed to create auth user');
  }

  const { data: appUser, error: insertError } = await supabaseAdmin
    .from('users')
    .insert({ auth_user_id: created.user.id, email, full_name: fullName, role })
    .select()
    .single();

  if (insertError) {
    // Roll back the auth user so we don't leave an orphaned account behind.
    await supabaseAdmin.auth.admin.deleteUser(created.user.id);
    throw new HttpError(400, insertError.message);
  }

  res.status(201).json({ user: appUser });
}
