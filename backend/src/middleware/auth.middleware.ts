import type { NextFunction, Request, Response } from 'express';
import { supabaseAdmin } from '../config/supabaseClient';
import type { UserRole } from '../types/domain';
import { HttpError } from './errorHandler.middleware';

/**
 * Verifies the bearer token issued by Supabase Auth and attaches the
 * corresponding `users` row (including app role) to req.authUser.
 *
 * Supabase Auth (not a parallel Express JWT scheme) is the source of
 * identity here because the Flutter client also talks to Supabase directly
 * for Realtime/RLS, both of which key off the same auth.uid().
 */
export function requireAuth() {
  return async (req: Request, _res: Response, next: NextFunction) => {
    const header = req.header('Authorization');
    const token = header?.startsWith('Bearer ') ? header.slice('Bearer '.length) : null;

    if (!token) {
      return next(new HttpError(401, 'Missing bearer token'));
    }

    const { data, error } = await supabaseAdmin.auth.getUser(token);
    if (error || !data.user) {
      return next(new HttpError(401, 'Invalid or expired token'));
    }

    const { data: appUser, error: userError } = await supabaseAdmin
      .from('users')
      .select('*')
      .eq('auth_user_id', data.user.id)
      .single();

    if (userError || !appUser) {
      return next(new HttpError(401, 'No application user linked to this account'));
    }

    req.authUser = appUser;
    next();
  };
}

export function requireRole(...roles: UserRole[]) {
  return (req: Request, _res: Response, next: NextFunction) => {
    if (!req.authUser) {
      return next(new HttpError(401, 'Authentication required'));
    }
    if (!roles.includes(req.authUser.role)) {
      return next(new HttpError(403, `Requires role: ${roles.join(' or ')}`));
    }
    next();
  };
}
