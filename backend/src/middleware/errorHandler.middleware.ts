import type { NextFunction, Request, Response } from 'express';
import { releaseIdempotencyKey } from '../services/idempotency.service';

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export function errorHandler(err: unknown, req: Request, res: Response, _next: NextFunction) {
  // A controller failed after claiming an idempotency key — release it so
  // the client can safely retry with the same key instead of being stuck
  // replaying a failed response forever.
  const idempotencyKey = req.header('Idempotency-Key');
  if (idempotencyKey) {
    releaseIdempotencyKey(idempotencyKey).catch((releaseErr) =>
      console.error('Failed to release idempotency key after error', releaseErr)
    );
  }

  if (err instanceof HttpError) {
    return res.status(err.status).json({ error: err.message });
  }

  console.error(err);
  return res.status(500).json({ error: 'Internal server error' });
}
