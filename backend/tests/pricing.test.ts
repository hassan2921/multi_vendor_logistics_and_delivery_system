import { fakeSupabase } from './fakeSupabase';

jest.mock('../src/config/supabaseClient', () => ({
  supabaseAdmin: fakeSupabase,
}));

import * as pricing from '../src/services/pricing.service';

// Defaults from env schema: base 199¢ + 60¢/km, capped at 999¢;
// platform fee 15%; courier keeps 80% of the delivery fee + all tips.

describe('pricing service', () => {
  beforeEach(() => {
    fakeSupabase.reset();
  });

  describe('haversineKm', () => {
    it('returns 0 for identical points', () => {
      expect(pricing.haversineKm(31.5204, 74.3587, 31.5204, 74.3587)).toBe(0);
    });

    it('computes a known distance (1 degree of latitude ≈ 111 km)', () => {
      const d = pricing.haversineKm(31, 74, 32, 74);
      expect(d).toBeGreaterThan(110);
      expect(d).toBeLessThan(112);
    });
  });

  describe('deliveryFeeCents', () => {
    it('charges nothing when no route could be established', () => {
      expect(pricing.deliveryFeeCents(null)).toBe(0);
    });

    it('charges base + per-km', () => {
      expect(pricing.deliveryFeeCents(2)).toBe(199 + 120);
    });

    it('caps the fee for long routes', () => {
      expect(pricing.deliveryFeeCents(100)).toBe(999);
    });
  });

  describe('estimateEtaMinutes', () => {
    it('is null without a route', () => {
      expect(pricing.estimateEtaMinutes(null)).toBeNull();
    });

    it('adds prep time to travel time', () => {
      // 25 km at 25 km/h = 60 min travel + 15 min prep
      expect(pricing.estimateEtaMinutes(25)).toBe(75);
    });
  });

  describe('marketplace splits', () => {
    it('takes the platform commission from the subtotal', () => {
      expect(pricing.platformFeeCents(1000)).toBe(150);
    });

    it('pays the courier their fee share plus the full tip', () => {
      expect(pricing.courierPayoutCents(500, 200)).toBe(400 + 200);
    });
  });

  describe('validatePromoCode', () => {
    async function seedPromo(overrides: Record<string, unknown> = {}) {
      await fakeSupabase.from('promo_codes').insert({
        code: 'SAVE10',
        discount_type: 'percent',
        discount_value: 10,
        min_subtotal_cents: 0,
        max_discount_cents: null,
        valid_from: null,
        valid_until: null,
        max_redemptions: null,
        redemption_count: 0,
        is_active: true,
        ...overrides,
      });
    }

    it('applies a percent discount and normalizes the code', async () => {
      await seedPromo();
      const { discountCents } = await pricing.validatePromoCode('  save10 ', 2000);
      expect(discountCents).toBe(200);
    });

    it('applies a fixed discount but never more than the subtotal', async () => {
      await seedPromo({ code: 'FLAT500', discount_type: 'fixed', discount_value: 500 });
      expect((await pricing.validatePromoCode('FLAT500', 2000)).discountCents).toBe(500);
      expect((await pricing.validatePromoCode('FLAT500', 300)).discountCents).toBe(300);
    });

    it('honors the max discount ceiling', async () => {
      await seedPromo({ discount_value: 50, max_discount_cents: 400 });
      expect((await pricing.validatePromoCode('SAVE10', 2000)).discountCents).toBe(400);
    });

    it('rejects unknown and inactive codes', async () => {
      await seedPromo({ is_active: false });
      await expect(pricing.validatePromoCode('SAVE10', 2000)).rejects.toMatchObject({ status: 422 });
      await expect(pricing.validatePromoCode('NOPE', 2000)).rejects.toMatchObject({ status: 422 });
    });

    it('rejects expired codes', async () => {
      await seedPromo({ valid_until: new Date(Date.now() - 1000).toISOString() });
      await expect(pricing.validatePromoCode('SAVE10', 2000)).rejects.toMatchObject({ status: 422 });
    });

    it('rejects codes below the minimum subtotal', async () => {
      await seedPromo({ min_subtotal_cents: 5000 });
      await expect(pricing.validatePromoCode('SAVE10', 2000)).rejects.toMatchObject({ status: 422 });
    });

    it('rejects fully redeemed codes', async () => {
      await seedPromo({ max_redemptions: 3, redemption_count: 3 });
      await expect(pricing.validatePromoCode('SAVE10', 2000)).rejects.toMatchObject({ status: 422 });
    });
  });
});
