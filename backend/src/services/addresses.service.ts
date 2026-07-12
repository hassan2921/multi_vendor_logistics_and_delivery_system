import { supabaseAdmin } from '../config/supabaseClient';
import { HttpError } from '../middleware/errorHandler.middleware';
import type { Address } from '../types/domain';

export async function listAddresses(userId: string): Promise<Address[]> {
  const { data, error } = await supabaseAdmin
    .from('addresses')
    .select('*')
    .eq('user_id', userId)
    .order('is_default', { ascending: false })
    .order('created_at', { ascending: false });

  if (error) {
    throw new HttpError(500, error.message);
  }
  return (data ?? []) as Address[];
}

export async function createAddress(
  userId: string,
  params: { label: string; addressLine: string; lat?: number; lng?: number; isDefault?: boolean }
): Promise<Address> {
  if (params.isDefault) {
    await clearDefault(userId);
  }

  const { data, error } = await supabaseAdmin
    .from('addresses')
    .insert({
      user_id: userId,
      label: params.label,
      address_line: params.addressLine,
      lat: params.lat ?? null,
      lng: params.lng ?? null,
      is_default: params.isDefault ?? false,
    })
    .select()
    .single();

  if (error || !data) {
    throw new HttpError(400, error?.message ?? 'Failed to save address');
  }
  return data as Address;
}

export async function updateAddress(
  userId: string,
  addressId: string,
  updates: Partial<{ label: string; addressLine: string; lat: number | null; lng: number | null; isDefault: boolean }>
): Promise<Address> {
  if (updates.isDefault) {
    await clearDefault(userId);
  }

  const patch: Record<string, unknown> = {};
  if (updates.label !== undefined) patch.label = updates.label;
  if (updates.addressLine !== undefined) patch.address_line = updates.addressLine;
  if (updates.lat !== undefined) patch.lat = updates.lat;
  if (updates.lng !== undefined) patch.lng = updates.lng;
  if (updates.isDefault !== undefined) patch.is_default = updates.isDefault;

  const { data, error } = await supabaseAdmin
    .from('addresses')
    .update(patch)
    .eq('id', addressId)
    .eq('user_id', userId) // ownership check baked into the query itself
    .select()
    .maybeSingle();

  if (error) {
    throw new HttpError(400, error.message);
  }
  if (!data) {
    throw new HttpError(404, 'Address not found');
  }
  return data as Address;
}

export async function deleteAddress(userId: string, addressId: string): Promise<void> {
  const { error } = await supabaseAdmin
    .from('addresses')
    .delete()
    .eq('id', addressId)
    .eq('user_id', userId);

  if (error) {
    throw new HttpError(400, error.message);
  }
}

async function clearDefault(userId: string): Promise<void> {
  await supabaseAdmin.from('addresses').update({ is_default: false }).eq('user_id', userId).eq('is_default', true);
}
