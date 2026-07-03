import { supabaseAdmin } from '../config/supabaseClient';
import type { Vendor } from '../types/domain';
import { HttpError } from '../middleware/errorHandler.middleware';

export async function listActiveVendors(): Promise<Vendor[]> {
  const { data, error } = await supabaseAdmin.from('vendors').select('*').eq('is_active', true);
  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []) as Vendor[];
}

export async function listOrdersForVendor(vendorId: string) {
  const { data, error } = await supabaseAdmin.from('orders').select('*').eq('vendor_id', vendorId);
  if (error) {
    throw new HttpError(500, error.message);
  }
  return data ?? [];
}
