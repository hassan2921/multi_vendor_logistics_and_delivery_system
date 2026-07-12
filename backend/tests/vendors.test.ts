import { fakeSupabase } from './fakeSupabase';

jest.mock('../src/config/supabaseClient', () => ({
  supabaseAdmin: fakeSupabase,
}));

import * as vendorsService from '../src/services/vendors.service';

describe('vendors service', () => {
  beforeEach(() => {
    fakeSupabase.reset();
  });

  describe('onboarding', () => {
    it('creates a vendor storefront for a new owner', async () => {
      const vendor = await vendorsService.createOrGetVendorForOwner('owner-1', { name: 'Pizza Place' });
      expect(vendor.name).toBe('Pizza Place');
      expect(vendor.owner_user_id).toBe('owner-1');
    });

    it('is idempotent — calling it again for the same owner returns the existing storefront', async () => {
      const first = await vendorsService.createOrGetVendorForOwner('owner-1', { name: 'Pizza Place' });
      const second = await vendorsService.createOrGetVendorForOwner('owner-1', { name: 'Different Name' });

      expect(second.id).toBe(first.id);
      expect(second.name).toBe('Pizza Place');
    });

    it('stores the cover photo URL when provided', async () => {
      const vendor = await vendorsService.createOrGetVendorForOwner('owner-1', {
        name: 'Pizza Place',
        imageUrl: 'https://cdn.example.com/pizza.jpg',
      });
      expect(vendor.image_url).toBe('https://cdn.example.com/pizza.jpg');
    });
  });

  describe('storefront profile updates', () => {
    it('updates name and cover photo', async () => {
      const vendor = await vendorsService.createOrGetVendorForOwner('owner-1', { name: 'Pizza Place' });

      const updated = await vendorsService.updateVendorProfile(vendor.id, {
        name: 'Pizza Palace',
        imageUrl: 'https://cdn.example.com/palace.jpg',
      });

      expect(updated.name).toBe('Pizza Palace');
      expect(updated.image_url).toBe('https://cdn.example.com/palace.jpg');
    });

    it('clears the cover photo when imageUrl is null', async () => {
      const vendor = await vendorsService.createOrGetVendorForOwner('owner-1', {
        name: 'Pizza Place',
        imageUrl: 'https://cdn.example.com/pizza.jpg',
      });

      const updated = await vendorsService.updateVendorProfile(vendor.id, { imageUrl: null });
      expect(updated.image_url).toBeNull();
    });

    it('404s for a vendor id that does not exist', async () => {
      await expect(
        vendorsService.updateVendorProfile('missing-vendor', { name: 'Ghost' })
      ).rejects.toMatchObject({ status: 404 });
    });
  });

  describe('product management', () => {
    it('lets a vendor create and then update their own product', async () => {
      const vendor = await vendorsService.createOrGetVendorForOwner('owner-1', { name: 'Pizza Place' });
      const product = await vendorsService.createProduct(vendor.id, { name: 'Margherita', priceCents: 1200 });

      const updated = await vendorsService.updateProduct(vendor.id, product.id, {
        priceCents: 1500,
        isAvailable: false,
      });

      expect(updated.price_cents).toBe(1500);
      expect(updated.is_available).toBe(false);
    });

    it('refuses to update a product belonging to a different vendor', async () => {
      const vendorA = await vendorsService.createOrGetVendorForOwner('owner-a', { name: 'A' });
      const vendorB = await vendorsService.createOrGetVendorForOwner('owner-b', { name: 'B' });
      const product = await vendorsService.createProduct(vendorA.id, { name: 'Margherita', priceCents: 1200 });

      await expect(
        vendorsService.updateProduct(vendorB.id, product.id, { priceCents: 1 })
      ).rejects.toMatchObject({ status: 404 });
    });

    it('only lists available products when onlyAvailable is set', async () => {
      const vendor = await vendorsService.createOrGetVendorForOwner('owner-1', { name: 'Pizza Place' });
      const available = await vendorsService.createProduct(vendor.id, { name: 'Margherita', priceCents: 1200 });
      const unavailable = await vendorsService.createProduct(vendor.id, { name: 'Seasonal', priceCents: 900 });
      await vendorsService.updateProduct(vendor.id, unavailable.id, { isAvailable: false });

      const menu = await vendorsService.listProductsForVendor(vendor.id, { onlyAvailable: true });
      expect(menu.map((p) => p.id)).toEqual([available.id]);
    });
  });
});
