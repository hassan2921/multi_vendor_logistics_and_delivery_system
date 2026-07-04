export type UserRole = 'customer' | 'courier' | 'vendor';

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

export interface AppUser {
  id: string;
  auth_user_id: string;
  email: string;
  role: UserRole;
  full_name: string | null;
}

export interface Vendor {
  id: string;
  owner_user_id: string;
  name: string;
  address: string | null;
  lat: number | null;
  lng: number | null;
  is_active: boolean;
}

export interface Product {
  id: string;
  vendor_id: string;
  name: string;
  description: string | null;
  price_cents: number;
  is_available: boolean;
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
  total_cents: number;
  currency: string;
  delivery_address: string | null;
  delivery_lat: number | null;
  delivery_lng: number | null;
}

export interface Payment {
  id: string;
  order_id: string;
  stripe_payment_intent_id: string | null;
  stripe_refund_id: string | null;
  status: string;
  amount_cents: number;
}

declare global {
  namespace Express {
    interface Request {
      authUser?: AppUser;
    }
  }
}

export {};
