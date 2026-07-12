import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import { addressesRouter } from './routes/addresses.routes';
import { adminRouter } from './routes/admin.routes';
import { authRouter } from './routes/auth.routes';
import { couriersRouter } from './routes/couriers.routes';
import { deliveriesRouter } from './routes/deliveries.routes';
import { notificationsRouter } from './routes/notifications.routes';
import { ordersRouter } from './routes/orders.routes';
import { paymentsRouter } from './routes/payments.routes';
import { vendorsRouter } from './routes/vendors.routes';
import * as paymentsController from './controllers/payments.controller';
import { errorHandler } from './middleware/errorHandler.middleware';
import { requestLogger } from './middleware/requestLogger.middleware';
import { asyncHandler } from './utils/asyncHandler';
import { rawBodyParser } from './utils/rawBody';

export function createApp() {
  const app = express();

  app.use(helmet());
  app.use(cors());
  app.use(requestLogger);

  // Mounted BEFORE express.json() — Stripe webhook signature verification
  // requires the exact raw request bytes, which express.json() would
  // otherwise consume and re-serialize, breaking the signature check.
  app.post('/payments/webhook', rawBodyParser, asyncHandler(paymentsController.webhook));

  app.use(express.json());

  app.get('/health', (_req, res) => res.json({ status: 'ok' }));

  app.use('/auth', authRouter);
  app.use('/orders', ordersRouter);
  app.use('/vendors', vendorsRouter);
  app.use('/deliveries', deliveriesRouter);
  app.use('/payments', paymentsRouter);
  app.use('/addresses', addressesRouter);
  app.use('/couriers', couriersRouter);
  app.use('/notifications', notificationsRouter);
  app.use('/admin', adminRouter);

  app.use(errorHandler);

  return app;
}
