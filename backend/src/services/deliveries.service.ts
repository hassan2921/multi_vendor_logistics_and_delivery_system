import { supabaseAdmin } from '../config/supabaseClient';
import { HttpError } from '../middleware/errorHandler.middleware';

export async function listAvailableJobs() {
  const { data, error } = await supabaseAdmin
    .from('orders')
    .select('*')
    .eq('status', 'ready_for_pickup')
    .is('courier_id', null);

  if (error) {
    throw new HttpError(500, error.message);
  }
  return data ?? [];
}
