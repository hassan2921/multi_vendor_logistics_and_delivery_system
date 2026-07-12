export type UserRole = 'customer' | 'courier' | 'vendor' | 'admin';

export type OrderStatus =
  | 'pending_payment'
  | 'paid'
  | 'accepted'
  | 'preparing'
  | 'ready_for_pickup'
  | 'courier_assigned'
  | 'picked_up'
  | 'in_transit'
  | 'delivered'
  | 'cancelled';

export type VendorApprovalStatus = 'pending' | 'approved' | 'rejected';

export interface AppUser {
  id: string;
  auth_user_id: string;
  email: string;
  role: UserRole;
  full_name: string | null;
  // Courier dispatch inputs: availability toggle + last reported position.
  is_available?: boolean;
  last_lat?: number | null;
  last_lng?: number | null;
  last_seen_at?: string | null;
}

export interface Vendor {
  id: string;
  owner_user_id: string;
  name: string;
  address: string | null;
  lat: number | null;
  lng: number | null;
  is_active: boolean;
  category: string | null;
  rating_avg: number;
  rating_count: number;
  approval_status: VendorApprovalStatus;
  stripe_account_id: string | null;
  payouts_enabled: boolean;
  image_url: string | null;
}

export interface Product {
  id: string;
  vendor_id: string;
  name: string;
  description: string | null;
  price_cents: number;
  is_available: boolean;
  category: string | null;
  /** null = inventory not tracked for this product */
  stock_quantity: number | null;
  image_url: string | null;
}

/** What the client sends: a reference to a catalog product, never a price. */
export interface OrderItemSelection {
  productId: string;
  quantity: number;
}

export interface Order {
  id: string;
  customer_id: string;
  vendor_id: string;
  courier_id: string | null;
  status: OrderStatus;
  subtotal_cents: number;
  delivery_fee_cents: number;
  tip_cents: number;
  discount_cents: number;
  promo_code: string | null;
  total_cents: number;
  currency: string;
  eta_minutes: number | null;
  scheduled_for: string | null;
  delivery_address: string | null;
  delivery_lat: number | null;
  delivery_lng: number | null;
}

/** Server-computed price preview, also embedded in every created order. */
export interface OrderQuote {
  subtotal_cents: number;
  delivery_fee_cents: number;
  discount_cents: number;
  tip_cents: number;
  total_cents: number;
  distance_km: number | null;
  eta_minutes: number | null;
  promo_code: string | null;
}

export interface Payment {
  id: string;
  order_id: string;
  stripe_payment_intent_id: string | null;
  stripe_refund_id: string | null;
  stripe_transfer_id: string | null;
  status: string;
  amount_cents: number;
  application_fee_cents: number;
}

export interface PromoCode {
  id: string;
  code: string;
  description: string | null;
  discount_type: 'percent' | 'fixed';
  discount_value: number;
  min_subtotal_cents: number;
  max_discount_cents: number | null;
  valid_from: string | null;
  valid_until: string | null;
  max_redemptions: number | null;
  redemption_count: number;
  is_active: boolean;
}

export interface Review {
  id: string;
  order_id: string;
  vendor_id: string;
  customer_id: string;
  rating: number;
  comment: string | null;
  created_at?: string;
}

export interface Address {
  id: string;
  user_id: string;
  label: string;
  address_line: string;
  lat: number | null;
  lng: number | null;
  is_default: boolean;
}

export interface Delivery {
  id: string;
  order_id: string;
  courier_id: string | null;
  status: string;
  assigned_at: string | null;
  delivered_at: string | null;
  courier_payout_cents: number;
  distance_km: number | null;
}

declare global {
  namespace Express {
    interface Request {
      authUser?: AppUser;
    }
  }
}

export {};
