import { Router } from 'express';
import { register } from '../controllers/auth.controller';
import { asyncHandler } from '../utils/asyncHandler';

export const authRouter = Router();

authRouter.post('/register', asyncHandler(register));
