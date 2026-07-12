import { Router } from 'express';
import * as notificationsController from '../controllers/notifications.controller';
import { requireAuth } from '../middleware/auth.middleware';
import { asyncHandler } from '../utils/asyncHandler';

export const notificationsRouter = Router();

notificationsRouter.post('/device-token', requireAuth(), asyncHandler(notificationsController.registerDeviceToken));
notificationsRouter.get('/', requireAuth(), asyncHandler(notificationsController.listMine));
notificationsRouter.post('/:id/read', requireAuth(), asyncHandler(notificationsController.markRead));
