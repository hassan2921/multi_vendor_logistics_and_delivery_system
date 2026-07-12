import { Router } from 'express';
import * as addressesController from '../controllers/addresses.controller';
import { requireAuth } from '../middleware/auth.middleware';
import { asyncHandler } from '../utils/asyncHandler';

export const addressesRouter = Router();

addressesRouter.get('/', requireAuth(), asyncHandler(addressesController.listMine));
addressesRouter.post('/', requireAuth(), asyncHandler(addressesController.create));
addressesRouter.patch('/:id', requireAuth(), asyncHandler(addressesController.update));
addressesRouter.delete('/:id', requireAuth(), asyncHandler(addressesController.remove));
