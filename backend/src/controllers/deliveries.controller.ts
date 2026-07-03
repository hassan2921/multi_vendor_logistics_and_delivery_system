import type { Request, Response } from 'express';
import * as deliveriesService from '../services/deliveries.service';

export async function listAvailableJobs(_req: Request, res: Response) {
  const jobs = await deliveriesService.listAvailableJobs();
  res.json({ jobs });
}
