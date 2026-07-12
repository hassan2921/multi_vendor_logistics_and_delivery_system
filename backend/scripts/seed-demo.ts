import { supabaseAdmin } from '../src/config/supabaseClient';
import {
  courierPayoutCents,
  deliveryFeeCents,
  estimateEtaMinutes,
  haversineKm,
  platformFeeCents,
} from '../src/services/pricing.service';
import type { UserRole } from '../src/types/domain';

/**
 * Seeds the Supabase project with a realistic demo dataset:
 * approved vendors with full menus, customers with saved addresses,
 * available couriers, a month of order history in every lifecycle state
 * (including live in-transit tracking pings), reviews, promo codes and
 * notification inboxes.
 *
 * Re-runnable: everything it creates hangs off `@demo.com` accounts, and it
 * deletes that slice (and only that slice) before inserting fresh data.
 *
 *   cd backend && npx tsx scripts/seed-demo.ts
 */

const DEMO_DOMAIN = '@demo.com';
const DEMO_PASSWORD = 'DemoPass123!';
const PROMO_CODES = ['WELCOME10', 'SAVE5', 'SUMMER25', 'SPRING15'];

// ── deterministic pseudo-randomness (same data every run) ──────────────────

let rngState = 42;
function rand(): number {
  rngState = (rngState * 1664525 + 1013904223) % 4294967296;
  return rngState / 4294967296;
}
const randInt = (min: number, max: number) => min + Math.floor(rand() * (max - min + 1));
const pick = <T>(arr: T[]): T => arr[Math.floor(rand() * arr.length)];

const daysAgo = (days: number, hourJitter = true) => {
  const d = new Date();
  d.setDate(d.getDate() - days);
  if (hourJitter) d.setHours(randInt(10, 21), randInt(0, 59), randInt(0, 59), 0);
  return d;
};
const minutesAgo = (minutes: number) => new Date(Date.now() - minutes * 60_000);

function fail(step: string, message?: string): never {
  console.error(`✗ ${step}: ${message ?? 'unknown error'}`);
  process.exit(1);
}

// ── cleanup: remove any previous demo slice ─────────────────────────────────

async function cleanup() {
  const demoAuthIds: string[] = [];
  for (let page = 1; page <= 20; page++) {
    const { data, error } = await supabaseAdmin.auth.admin.listUsers({ page, perPage: 200 });
    if (error) fail('listing auth users', error.message);
    for (const u of data.users) {
      if (u.email?.endsWith(DEMO_DOMAIN)) demoAuthIds.push(u.id);
    }
    if (data.users.length < 200) break;
  }

  if (demoAuthIds.length > 0) {
    const { data: userRows } = await supabaseAdmin
      .from('users')
      .select('id')
      .in('auth_user_id', demoAuthIds);
    const userIds = (userRows ?? []).map((r) => r.id as string);

    if (userIds.length > 0) {
      // Orders cascade to order_items, deliveries, location_pings, payments
      // and reviews; auth-user deletion cascades to users, addresses,
      // notifications and device_tokens. Vendors must go after their orders.
      const { error: ordersError } = await supabaseAdmin
        .from('orders')
        .delete()
        .in('customer_id', userIds);
      if (ordersError) fail('deleting old demo orders', ordersError.message);

      const { error: vendorsError } = await supabaseAdmin
        .from('vendors')
        .delete()
        .in('owner_user_id', userIds);
      if (vendorsError) fail('deleting old demo vendors', vendorsError.message);
    }

    for (const authId of demoAuthIds) {
      const { error } = await supabaseAdmin.auth.admin.deleteUser(authId);
      if (error) fail(`deleting auth user ${authId}`, error.message);
    }
    console.log(`  removed previous demo slice (${demoAuthIds.length} accounts)`);
  }

  await supabaseAdmin.from('promo_codes').delete().in('code', PROMO_CODES);
}

// ── accounts ────────────────────────────────────────────────────────────────

interface SeedUser {
  id: string;
  email: string;
  full_name: string;
}

async function createAccount(
  email: string,
  fullName: string,
  role: UserRole,
  extra: Record<string, unknown> = {}
): Promise<SeedUser> {
  const { data: created, error: authError } = await supabaseAdmin.auth.admin.createUser({
    email,
    password: DEMO_PASSWORD,
    email_confirm: true,
  });
  if (authError || !created.user) fail(`creating auth user ${email}`, authError?.message);

  const { data, error } = await supabaseAdmin
    .from('users')
    .insert({ auth_user_id: created.user.id, email, full_name: fullName, role, ...extra })
    .select('id')
    .single();
  if (error || !data) fail(`creating users row for ${email}`, error?.message);

  return { id: data.id as string, email, full_name: fullName };
}

// ── vendor catalog ──────────────────────────────────────────────────────────

interface SeedProductSpec {
  name: string;
  description: string;
  price: number; // cents
  category: string;
  stock?: number; // omitted = inventory not tracked
  image: string; // Unsplash photo id (verified to resolve)
}

interface SeedVendorSpec {
  slug: string;
  name: string;
  category: string;
  address: string;
  lat: number;
  lng: number;
  owner: string;
  image: string; // Unsplash photo id — storefront cover
  products: SeedProductSpec[];
}

/** Sized-down Unsplash CDN URL — small enough for list thumbnails. */
const img = (id: string) => `https://images.unsplash.com/${id}?w=400&q=60&auto=format&fit=crop`;

// All coordinates are around Lower/Midtown Manhattan so distances, fees and
// ETAs come out realistic for an urban delivery marketplace.
const VENDOR_SPECS: SeedVendorSpec[] = [
  {
    slug: 'bella',
    name: 'Bella Napoli Pizzeria',
    category: 'Pizza & Italian',
    address: '145 Mulberry St, New York, NY 10013',
    lat: 40.7194,
    lng: -73.9973,
    owner: 'Giuseppe Romano',
    image: 'photo-1555396273-367ea4eb4db5',
    products: [
      { name: 'Margherita Pizza', description: 'San Marzano tomatoes, fresh mozzarella, basil, extra-virgin olive oil', price: 1495, category: 'Pizza', image: 'photo-1574071318508-1cdbab80d002' },
      { name: 'Pepperoni Pizza', description: 'Crispy cup pepperoni, mozzarella, oregano', price: 1695, category: 'Pizza', image: 'photo-1628840042765-356cda07504e' },
      { name: 'Quattro Formaggi', description: 'Mozzarella, gorgonzola, parmesan and fontina on a white base', price: 1795, category: 'Pizza', image: 'photo-1513104890138-7c749659a591' },
      { name: 'Prosciutto e Rucola', description: 'Parma ham, wild arugula, shaved parmesan', price: 1895, category: 'Pizza', image: 'photo-1571407970349-bc81e7e96d47' },
      { name: 'Spaghetti Carbonara', description: 'Guanciale, pecorino romano, egg yolk, cracked pepper', price: 1650, category: 'Pasta', image: 'photo-1612874742237-6526221588e3' },
      { name: 'Lasagna della Nonna', description: 'Slow-braised beef ragù layered with béchamel', price: 1750, category: 'Pasta', image: 'photo-1619895092538-128341789043' },
      { name: 'Caprese Salad', description: 'Buffalo mozzarella, heirloom tomatoes, basil, balsamic glaze', price: 1150, category: 'Starters', image: 'photo-1608897013039-887f21d8c804' },
      { name: 'Garlic Knots (6 pc)', description: 'House dough knots tossed in garlic butter and parsley', price: 595, category: 'Starters', image: 'photo-1573140247632-f8fd74997d5c' },
      { name: 'Tiramisu', description: 'Espresso-soaked ladyfingers, mascarpone cream, cocoa', price: 850, category: 'Desserts', image: 'photo-1571877227200-a0d98ea607e9' },
      { name: 'San Pellegrino (500ml)', description: 'Sparkling mineral water', price: 350, category: 'Drinks', stock: 48, image: 'photo-1523362628745-0c100150b504' },
    ],
  },
  {
    slug: 'dragonwok',
    name: 'Dragon Wok',
    category: 'Chinese',
    address: '88 Bayard St, New York, NY 10013',
    lat: 40.7158,
    lng: -73.9986,
    owner: 'Wei Zhang',
    image: 'photo-1526318896980-cf78c088247c',
    products: [
      { name: 'General Tso\'s Chicken', description: 'Crispy chicken in sweet-spicy glaze with steamed broccoli', price: 1425, category: 'Mains', image: 'photo-1525755662778-989d0524087e' },
      { name: 'Beef & Broccoli', description: 'Wok-seared flank steak in ginger-garlic sauce', price: 1550, category: 'Mains', image: 'photo-1603133872878-684f208fb84b' },
      { name: 'Kung Pao Shrimp', description: 'Szechuan peppercorns, roasted peanuts, dried chilies', price: 1675, category: 'Mains', image: 'photo-1518492104633-130d0cc84637' },
      { name: 'Mapo Tofu', description: 'Silken tofu in fiery chili-bean sauce (vegetarian)', price: 1250, category: 'Mains', image: 'photo-1541696432-82c6da8ce7bf' },
      { name: 'Pork Soup Dumplings (8 pc)', description: 'Hand-folded xiao long bao with rich pork broth', price: 1095, category: 'Dim Sum', image: 'photo-1496116218417-1a781b1c416c' },
      { name: 'Vegetable Spring Rolls (4 pc)', description: 'Crispy rolls with sweet chili dip', price: 650, category: 'Dim Sum', image: 'photo-1544025162-d76694265947' },
      { name: 'Yang Chow Fried Rice', description: 'Shrimp, char siu pork, egg and scallions', price: 1195, category: 'Rice & Noodles', image: 'photo-1512058564366-18510be2db19' },
      { name: 'Dan Dan Noodles', description: 'Hand-pulled noodles, minced pork, chili oil, sesame', price: 1275, category: 'Rice & Noodles', image: 'photo-1569718212165-3a8278d5f624' },
      { name: 'Hot & Sour Soup', description: 'Classic pepper-vinegar broth with tofu and mushroom', price: 595, category: 'Soups', image: 'photo-1547592166-23ac45744acd' },
    ],
  },
  {
    slug: 'greenbowl',
    name: 'Green Bowl Kitchen',
    category: 'Healthy & Salads',
    address: '210 Lafayette St, New York, NY 10012',
    lat: 40.7225,
    lng: -73.9985,
    owner: 'Maya Patel',
    image: 'photo-1490645935967-10de6ba17061',
    products: [
      { name: 'Harvest Grain Bowl', description: 'Quinoa, roasted sweet potato, kale, tahini dressing', price: 1350, category: 'Bowls', image: 'photo-1512621776951-a57141f2eefd' },
      { name: 'Chicken Pesto Bowl', description: 'Grilled chicken, brown rice, cherry tomatoes, basil pesto', price: 1495, category: 'Bowls', image: 'photo-1546069901-ba9599a7e63c' },
      { name: 'Spicy Salmon Poke', description: 'Sushi-grade salmon, edamame, avocado, sriracha mayo', price: 1695, category: 'Bowls', image: 'photo-1546069901-d5bfd2cbfb1f' },
      { name: 'Kale Caesar', description: 'Lacinato kale, sourdough croutons, shaved parmesan', price: 1195, category: 'Salads', image: 'photo-1550304943-4f24f54ddde9' },
      { name: 'Mediterranean Chop', description: 'Cucumber, feta, olives, chickpeas, red-wine vinaigrette', price: 1250, category: 'Salads', image: 'photo-1540189549336-e6e99c3679fe' },
      { name: 'Avocado Toast', description: 'Smashed avocado, chili flakes, lemon on multigrain', price: 950, category: 'Toasts', image: 'photo-1588137378633-dea1336ce1e2' },
      { name: 'Green Machine Smoothie', description: 'Spinach, mango, banana, coconut water', price: 795, category: 'Drinks', image: 'photo-1610970881699-44a5587cabec' },
      { name: 'Cold-Pressed Ginger Shot', description: 'Ginger, turmeric, lemon, cayenne', price: 450, category: 'Drinks', stock: 30, image: 'photo-1622597467836-f3285f2131b8' },
    ],
  },
  {
    slug: 'burgerbarn',
    name: 'Burger Barn',
    category: 'Burgers & American',
    address: '327 W 42nd St, New York, NY 10036',
    lat: 40.757,
    lng: -73.9903,
    owner: 'Jake Sullivan',
    image: 'photo-1552566626-52f8b828add9',
    products: [
      { name: 'Classic Smash Burger', description: 'Double smashed patties, American cheese, pickles, barn sauce', price: 1195, category: 'Burgers', image: 'photo-1568901346375-23c9450c58cd' },
      { name: 'Bacon BBQ Stack', description: 'Applewood bacon, cheddar, crispy onions, bourbon BBQ', price: 1450, category: 'Burgers', image: 'photo-1553979459-d2229ba7433b' },
      { name: 'Mushroom Swiss', description: 'Sautéed cremini mushrooms, swiss, garlic aioli', price: 1350, category: 'Burgers', image: 'photo-1607013251379-e6eecfffe234' },
      { name: 'Crispy Chicken Sandwich', description: 'Buttermilk-fried thigh, slaw, spicy mayo, brioche', price: 1275, category: 'Sandwiches', image: 'photo-1606755962773-d324e0a13086' },
      { name: 'Beyond Veggie Burger', description: 'Plant-based patty, vegan cheddar, lettuce, tomato', price: 1395, category: 'Burgers', image: 'photo-1520072959219-c595dc870360' },
      { name: 'Hand-Cut Fries', description: 'Twice-fried russets with sea salt', price: 495, category: 'Sides', image: 'photo-1573080496219-bb080dd4f877' },
      { name: 'Loaded Cheese Fries', description: 'Cheddar sauce, bacon bits, scallions, ranch', price: 795, category: 'Sides', image: 'photo-1585109649139-366815a0d713' },
      { name: 'Onion Rings', description: 'Beer-battered thick-cut rings with chipotle dip', price: 650, category: 'Sides', image: 'photo-1639024471283-03518883512d' },
      { name: 'Vanilla Milkshake', description: 'Hand-spun with Madagascar vanilla ice cream', price: 695, category: 'Shakes', image: 'photo-1579954115545-a95591f28bfc' },
      { name: 'Oreo Milkshake', description: 'Cookies-and-cream shake with whipped topping', price: 745, category: 'Shakes', image: 'photo-1572490122747-3968b75cc699' },
    ],
  },
  {
    slug: 'sakura',
    name: 'Sakura Sushi House',
    category: 'Japanese & Sushi',
    address: '414 E 9th St, New York, NY 10009',
    lat: 40.7276,
    lng: -73.9838,
    owner: 'Kenji Tanaka',
    image: 'photo-1517248135467-4c7edcad34c4',
    products: [
      { name: 'Salmon Nigiri (2 pc)', description: 'Scottish salmon over seasoned rice', price: 650, category: 'Nigiri', image: 'photo-1579871494447-9811cf80d66c' },
      { name: 'Tuna Nigiri (2 pc)', description: 'Bluefin akami over seasoned rice', price: 750, category: 'Nigiri', image: 'photo-1553621042-f6e147245754' },
      { name: 'California Roll (8 pc)', description: 'Snow crab, avocado, cucumber, tobiko', price: 995, category: 'Rolls', image: 'photo-1579584425555-c3ce17fd4351' },
      { name: 'Spicy Tuna Roll (8 pc)', description: 'Chopped tuna, sriracha mayo, scallion, tempura crunch', price: 1150, category: 'Rolls', image: 'photo-1611143669185-af224c5e3252' },
      { name: 'Dragon Roll (8 pc)', description: 'Shrimp tempura topped with eel and avocado', price: 1650, category: 'Rolls', image: 'photo-1617196034796-73dfa7b1fd56' },
      { name: 'Chirashi Bowl', description: 'Chef\'s selection of 12 sashimi cuts over sushi rice', price: 2450, category: 'Bowls', image: 'photo-1563612116625-3012372fccce' },
      { name: 'Chicken Teriyaki Bento', description: 'Grilled chicken, rice, gyoza, side salad, miso soup', price: 1750, category: 'Bento', image: 'photo-1569050467447-ce54b3bbc37d' },
      { name: 'Miso Soup', description: 'Wakame, tofu, scallion', price: 395, category: 'Sides', image: 'photo-1547592180-85f173990554' },
      { name: 'Seaweed Salad', description: 'Sesame-marinated wakame', price: 595, category: 'Sides', image: 'photo-1622973536968-3ead9e780960' },
    ],
  },
  {
    slug: 'freshmart',
    name: 'FreshMart Grocery',
    category: 'Grocery',
    address: '52 Avenue A, New York, NY 10009',
    lat: 40.7243,
    lng: -73.9838,
    owner: 'Omar Farouk',
    image: 'photo-1542838132-92c53300491e',
    products: [
      { name: 'Organic Bananas (bunch)', description: 'Fair-trade organic bananas, ~6 per bunch', price: 249, category: 'Produce', stock: 120, image: 'photo-1571771894821-ce9b6c11b08e' },
      { name: 'Hass Avocados (2 pc)', description: 'Ready-to-eat ripeness', price: 399, category: 'Produce', stock: 80, image: 'photo-1523049673857-eb18f1d7b578' },
      { name: 'Whole Milk (1 gal)', description: 'Grade A pasteurized, local dairy', price: 549, category: 'Dairy', stock: 40, image: 'photo-1550583724-b2692b85b150' },
      { name: 'Free-Range Eggs (dozen)', description: 'Large brown eggs, certified humane', price: 629, category: 'Dairy', stock: 60, image: 'photo-1506976785307-8732e854ad03' },
      { name: 'Sourdough Loaf', description: 'Naturally leavened, baked daily', price: 699, category: 'Bakery', stock: 25, image: 'photo-1509440159596-0249088772ff' },
      { name: 'Chicken Breast (1 lb)', description: 'Air-chilled boneless skinless', price: 899, category: 'Meat', stock: 35, image: 'photo-1604503468506-a8da13d82791' },
      { name: 'Basmati Rice (5 lb)', description: 'Extra-long grain aged basmati', price: 1199, category: 'Pantry', stock: 50, image: 'photo-1586201375761-83865001e31c' },
      { name: 'Extra-Virgin Olive Oil (750ml)', description: 'Cold-pressed Italian EVOO', price: 1499, category: 'Pantry', stock: 30, image: 'photo-1474979266404-7eaacbcd87c5' },
      { name: 'Orange Juice (52 oz)', description: 'Fresh-squeezed, no pulp', price: 649, category: 'Beverages', stock: 45, image: 'photo-1600271886742-f049cd451bba' },
      { name: 'Sparkling Water 12-pack', description: 'Lime flavored, zero calories', price: 799, category: 'Beverages', stock: 55, image: 'photo-1560023907-5f339617ea30' },
    ],
  },
  {
    slug: 'quickmeds',
    name: 'QuickMeds Pharmacy',
    category: 'Pharmacy & Wellness',
    address: '160 W 26th St, New York, NY 10001',
    lat: 40.7452,
    lng: -73.9937,
    owner: 'Dr. Anita Shah',
    image: 'photo-1576602976047-174e57a47881',
    products: [
      { name: 'Ibuprofen 200mg (50 ct)', description: 'Pain reliever / fever reducer tablets', price: 849, category: 'Medicine', stock: 90, image: 'photo-1584308666744-24d5c474f2ae' },
      { name: 'Acetaminophen 500mg (100 ct)', description: 'Extra-strength pain relief caplets', price: 1049, category: 'Medicine', stock: 75, image: 'photo-1471864190281-a93a3070b6de' },
      { name: 'Allergy Relief 24hr (30 ct)', description: 'Non-drowsy loratadine tablets', price: 1299, category: 'Medicine', stock: 60, image: 'photo-1587854692152-cbe660dbde88' },
      { name: 'Digital Thermometer', description: '10-second oral/underarm readings', price: 1599, category: 'Health Devices', stock: 20, image: 'photo-1584362917165-526a968579e8' },
      { name: 'Adhesive Bandages (100 ct)', description: 'Assorted flexible fabric sizes', price: 599, category: 'First Aid', stock: 110, image: 'photo-1603398938378-e54eab446dde' },
      { name: 'Vitamin D3 2000 IU (120 ct)', description: 'Daily immune support softgels', price: 1149, category: 'Vitamins', stock: 65, image: 'photo-1550572017-edd951b55104' },
      { name: 'Multivitamin Gummies (90 ct)', description: 'Adult daily multivitamin, mixed fruit', price: 1399, category: 'Vitamins', stock: 45, image: 'photo-1607619056574-7b8d3ee536b2' },
      { name: 'Hand Sanitizer (8 oz)', description: '70% alcohol gel with aloe', price: 449, category: 'Personal Care', stock: 130, image: 'photo-1584744982491-665216d95f8b' },
    ],
  },
  {
    slug: 'sweetcrumb',
    name: 'Sweet Crumb Bakery',
    category: 'Bakery & Desserts',
    address: '250 Bleecker St, New York, NY 10014',
    lat: 40.7315,
    lng: -74.0031,
    owner: 'Claire Dubois',
    image: 'photo-1517433670267-08bbd4be890f',
    products: [
      { name: 'Butter Croissant', description: 'Laminated 72-hour dough, French butter', price: 425, category: 'Pastries', stock: 40, image: 'photo-1555507036-ab1f4038808a' },
      { name: 'Almond Croissant', description: 'Twice-baked with frangipane and toasted almonds', price: 525, category: 'Pastries', stock: 30, image: 'photo-1623334044303-241021148842' },
      { name: 'Pain au Chocolat', description: 'Dark Valrhona chocolate batons', price: 475, category: 'Pastries', stock: 35, image: 'photo-1509365465985-25d11c17e812' },
      { name: 'NY Cheesecake Slice', description: 'Classic baked cheesecake, graham crust', price: 695, category: 'Cakes', image: 'photo-1533134242443-d4fd215305ad' },
      { name: 'Chocolate Fudge Cake Slice', description: 'Triple-layer with dark ganache', price: 725, category: 'Cakes', image: 'photo-1578985545062-69928b1d9587' },
      { name: 'Macarons (6 pc)', description: 'Assorted: pistachio, raspberry, salted caramel', price: 1450, category: 'Sweets', stock: 22, image: 'photo-1569864358642-9d1684040f43' },
      { name: 'Chocolate Chip Cookies (4 pc)', description: 'Brown-butter dough, sea salt finish', price: 795, category: 'Sweets', image: 'photo-1499636136210-6f4ee915583e' },
      { name: 'Cold Brew Coffee', description: '18-hour steeped single origin', price: 550, category: 'Drinks', image: 'photo-1461023058943-07fcbe16d735' },
    ],
  },
];

// ── customers, couriers, addresses ─────────────────────────────────────────

const CUSTOMER_SPECS = [
  { email: `customer${DEMO_DOMAIN}`, name: 'Sarah Mitchell' },
  { email: `james.carter${DEMO_DOMAIN}`, name: 'James Carter' },
  { email: `emily.rodriguez${DEMO_DOMAIN}`, name: 'Emily Rodriguez' },
  { email: `michael.chen${DEMO_DOMAIN}`, name: 'Michael Chen' },
  { email: `fatima.noor${DEMO_DOMAIN}`, name: 'Fatima Noor' },
];

const COURIER_SPECS = [
  { email: `courier${DEMO_DOMAIN}`, name: 'Marcus Webb', lat: 40.7223, lng: -73.9957 },
  { email: `dana.kim${DEMO_DOMAIN}`, name: 'Dana Kim', lat: 40.7431, lng: -73.9911 },
  { email: `luis.alvarez${DEMO_DOMAIN}`, name: 'Luis Alvarez', lat: 40.7291, lng: -73.9884 },
];

// One primary address per customer (used on their orders) plus extras.
const ADDRESS_SPECS: Array<{ label: string; line: string; lat: number; lng: number }[]> = [
  [
    { label: 'Home', line: '77 Bleecker St, Apt 4B, New York, NY 10012', lat: 40.7265, lng: -73.9959 },
    { label: 'Work', line: '335 Madison Ave, Fl 16, New York, NY 10017', lat: 40.7527, lng: -73.9788 },
  ],
  [
    { label: 'Home', line: '245 E 13th St, Apt 2A, New York, NY 10003', lat: 40.7317, lng: -73.9852 },
  ],
  [
    { label: 'Home', line: '509 W 38th St, Apt 12C, New York, NY 10018', lat: 40.7563, lng: -73.9986 },
    { label: 'Gym', line: '60 W 23rd St, New York, NY 10010', lat: 40.7424, lng: -73.9914 },
  ],
  [
    { label: 'Home', line: '180 Orchard St, Apt 8F, New York, NY 10002', lat: 40.7213, lng: -73.988 },
  ],
  [
    { label: 'Home', line: '405 W 50th St, Apt 3D, New York, NY 10019', lat: 40.7632, lng: -73.9884 },
    { label: 'Office', line: '1 Union Sq W, New York, NY 10003', lat: 40.7359, lng: -73.9911 },
  ],
];

const REVIEW_COMMENTS: Record<number, string[]> = {
  5: [
    'Absolutely delicious and arrived hot. Will definitely order again!',
    'Best in the neighborhood, hands down. Courier was super friendly too.',
    'Fresh, fast, perfectly packed. Five stars all the way.',
    'Exceeded expectations — generous portions and great value.',
    'My go-to spot now. Everything came exactly as ordered.',
  ],
  4: [
    'Really good food, delivery took a little longer than the estimate.',
    'Tasty and well packaged. Fries could have been crispier.',
    'Great quality overall, would order again.',
    'Solid meal, slightly smaller portion than last time.',
  ],
  3: [
    'Food was okay but arrived lukewarm.',
    'Average experience — nothing wrong, nothing special.',
    'Decent, though they forgot the extra sauce I asked for.',
  ],
};

// ── main ────────────────────────────────────────────────────────────────────

async function main() {
  console.log('Cleaning up previous demo data…');
  await cleanup();

  console.log('Creating accounts…');
  await createAccount(`admin${DEMO_DOMAIN}`, 'Platform Admin', 'admin');

  const customers: SeedUser[] = [];
  for (const spec of CUSTOMER_SPECS) {
    customers.push(await createAccount(spec.email, spec.name, 'customer'));
  }

  const couriers: SeedUser[] = [];
  for (const spec of COURIER_SPECS) {
    couriers.push(
      await createAccount(spec.email, spec.name, 'courier', {
        is_available: true,
        last_lat: spec.lat,
        last_lng: spec.lng,
        last_seen_at: minutesAgo(randInt(1, 10)).toISOString(),
      })
    );
  }

  console.log('Creating vendors and menus…');
  const vendors: Array<{
    id: string;
    name: string;
    lat: number;
    lng: number;
    ownerId: string;
    products: Array<{ id: string; name: string; price_cents: number }>;
  }> = [];

  for (const spec of VENDOR_SPECS) {
    const owner = await createAccount(
      spec.slug === 'bella' ? `vendor${DEMO_DOMAIN}` : `vendor.${spec.slug}${DEMO_DOMAIN}`,
      spec.owner,
      'vendor'
    );

    const { data: vendorRow, error: vendorError } = await supabaseAdmin
      .from('vendors')
      .insert({
        owner_user_id: owner.id,
        name: spec.name,
        address: spec.address,
        lat: spec.lat,
        lng: spec.lng,
        is_active: true,
        category: spec.category,
        image_url: img(spec.image),
        approval_status: 'approved',
        created_at: daysAgo(randInt(45, 90)).toISOString(),
      })
      .select('id')
      .single();
    if (vendorError || !vendorRow) fail(`creating vendor ${spec.name}`, vendorError?.message);

    const { data: productRows, error: productsError } = await supabaseAdmin
      .from('products')
      .insert(
        spec.products.map((p) => ({
          vendor_id: vendorRow.id,
          name: p.name,
          description: p.description,
          price_cents: p.price,
          is_available: true,
          category: p.category,
          stock_quantity: p.stock ?? null,
          image_url: img(p.image),
        }))
      )
      .select('id, name, price_cents');
    if (productsError || !productRows) fail(`creating products for ${spec.name}`, productsError?.message);

    vendors.push({
      id: vendorRow.id as string,
      name: spec.name,
      lat: spec.lat,
      lng: spec.lng,
      ownerId: owner.id,
      products: productRows as Array<{ id: string; name: string; price_cents: number }>,
    });
  }

  console.log('Creating saved addresses…');
  for (let i = 0; i < customers.length; i++) {
    const { error } = await supabaseAdmin.from('addresses').insert(
      ADDRESS_SPECS[i].map((a, idx) => ({
        user_id: customers[i].id,
        label: a.label,
        address_line: a.line,
        lat: a.lat,
        lng: a.lng,
        is_default: idx === 0,
      }))
    );
    if (error) fail(`creating addresses for ${customers[i].email}`, error.message);
  }

  console.log('Creating promo codes…');
  {
    const { error } = await supabaseAdmin.from('promo_codes').insert([
      {
        code: 'WELCOME10',
        description: '10% off your first order (up to $5)',
        discount_type: 'percent',
        discount_value: 10,
        min_subtotal_cents: 1000,
        max_discount_cents: 500,
        max_redemptions: 500,
        redemption_count: 137,
        is_active: true,
      },
      {
        code: 'SAVE5',
        description: '$5 off orders over $25',
        discount_type: 'fixed',
        discount_value: 500,
        min_subtotal_cents: 2500,
        max_redemptions: 200,
        redemption_count: 64,
        is_active: true,
      },
      {
        code: 'SUMMER25',
        description: 'Summer special — 25% off (up to $10)',
        discount_type: 'percent',
        discount_value: 25,
        min_subtotal_cents: 3000,
        max_discount_cents: 1000,
        valid_until: new Date(Date.now() + 45 * 86_400_000).toISOString(),
        max_redemptions: 100,
        redemption_count: 18,
        is_active: true,
      },
      {
        code: 'SPRING15',
        description: 'Spring promo (expired)',
        discount_type: 'percent',
        discount_value: 15,
        min_subtotal_cents: 2000,
        max_discount_cents: 750,
        valid_until: daysAgo(20, false).toISOString(),
        max_redemptions: 100,
        redemption_count: 100,
        is_active: false,
      },
    ]);
    if (error) fail('creating promo codes', error.message);
  }

  // ── orders ────────────────────────────────────────────────────────────────

  console.log('Creating orders…');

  interface OrderPlan {
    status: string;
    daysBack: number;
    courier: SeedUser | null;
    minutesActive?: number; // for today's live orders
  }

  const reviewRows: Array<{
    order_id: string;
    vendor_id: string;
    customer_id: string;
    rating: number;
    comment: string | null;
    created_at: string;
  }> = [];
  const notificationRows: Array<{
    user_id: string;
    title: string;
    body: string;
    data: Record<string, unknown>;
    read: boolean;
    created_at: string;
  }> = [];

  let orderCount = 0;
  let inTransitInfo: { deliveryId: string; courier: SeedUser } | null = null;

  async function createOrder(plan: OrderPlan) {
    const customerIdx = randInt(0, customers.length - 1);
    const customer = customers[customerIdx];
    const vendor = pick(vendors);
    const dropoff = ADDRESS_SPECS[customerIdx][0];

    // 1–4 line items snapshotting catalog names and prices.
    const chosen = new Map<string, { product: (typeof vendor.products)[0]; qty: number }>();
    for (let i = 0, n = randInt(1, 4); i < n; i++) {
      const product = pick(vendor.products);
      const existing = chosen.get(product.id);
      if (existing) existing.qty += 1;
      else chosen.set(product.id, { product, qty: randInt(1, 2) });
    }
    const items = [...chosen.values()];
    const subtotal = items.reduce((sum, it) => sum + it.product.price_cents * it.qty, 0);

    const distanceKm = haversineKm(vendor.lat, vendor.lng, dropoff.lat, dropoff.lng);
    const fee = deliveryFeeCents(distanceKm);
    const eta = estimateEtaMinutes(distanceKm);
    const tip = rand() < 0.6 ? pick([100, 200, 300, 500]) : 0;

    let discount = 0;
    let promoCode: string | null = null;
    if (rand() < 0.25) {
      if (subtotal >= 2500 && rand() < 0.5) {
        promoCode = 'SAVE5';
        discount = 500;
      } else if (subtotal >= 1000) {
        promoCode = 'WELCOME10';
        discount = Math.min(Math.floor(subtotal * 0.1), 500);
      }
    }
    const total = subtotal + fee + tip - discount;

    const createdAt =
      plan.minutesActive !== undefined ? minutesAgo(plan.minutesActive) : daysAgo(plan.daysBack);
    const updatedAt =
      plan.minutesActive !== undefined
        ? minutesAgo(Math.max(1, Math.floor(plan.minutesActive / 3)))
        : new Date(createdAt.getTime() + randInt(30, 70) * 60_000);

    const { data: orderRow, error: orderError } = await supabaseAdmin
      .from('orders')
      .insert({
        customer_id: customer.id,
        vendor_id: vendor.id,
        courier_id: plan.courier?.id ?? null,
        status: plan.status,
        subtotal_cents: subtotal,
        delivery_fee_cents: fee,
        tip_cents: tip,
        discount_cents: discount,
        promo_code: promoCode,
        total_cents: total,
        currency: 'usd',
        eta_minutes: eta,
        delivery_address: dropoff.line,
        delivery_lat: dropoff.lat,
        delivery_lng: dropoff.lng,
        created_at: createdAt.toISOString(),
        updated_at: updatedAt.toISOString(),
      })
      .select('id')
      .single();
    if (orderError || !orderRow) fail('creating order', orderError?.message);
    const orderId = orderRow.id as string;
    orderCount++;

    const { error: itemsError } = await supabaseAdmin.from('order_items').insert(
      items.map((it) => ({
        order_id: orderId,
        product_id: it.product.id,
        name: it.product.name,
        quantity: it.qty,
        unit_price_cents: it.product.price_cents,
      }))
    );
    if (itemsError) fail('creating order items', itemsError.message);

    // Delivery row mirroring the order's lifecycle stage.
    const delivered = plan.status === 'delivered';
    const enRoute = ['courier_assigned', 'picked_up', 'in_transit'].includes(plan.status);
    const { data: deliveryRow, error: deliveryError } = await supabaseAdmin
      .from('deliveries')
      .insert({
        order_id: orderId,
        courier_id: plan.courier?.id ?? null,
        status: delivered ? 'delivered' : enRoute ? 'assigned' : 'unassigned',
        assigned_at:
          delivered || enRoute
            ? new Date(createdAt.getTime() + randInt(8, 15) * 60_000).toISOString()
            : null,
        delivered_at: delivered ? updatedAt.toISOString() : null,
        courier_payout_cents: delivered ? courierPayoutCents(fee, tip) : 0,
        distance_km: Math.round(distanceKm * 100) / 100,
      })
      .select('id')
      .single();
    if (deliveryError || !deliveryRow) fail('creating delivery', deliveryError?.message);

    // Payment row for anything that got past checkout.
    if (plan.status !== 'pending_payment') {
      const refunded = plan.status === 'cancelled' && rand() < 0.5;
      const { error: paymentError } = await supabaseAdmin.from('payments').insert({
        order_id: orderId,
        stripe_payment_intent_id: `pi_demo_${orderId.slice(0, 8)}${randInt(1000, 9999)}`,
        stripe_refund_id: refunded ? `re_demo_${orderId.slice(0, 8)}` : null,
        status: refunded ? 'refunded' : 'succeeded',
        amount_cents: total,
        application_fee_cents: platformFeeCents(subtotal),
        created_at: createdAt.toISOString(),
        updated_at: updatedAt.toISOString(),
      });
      if (paymentError) fail('creating payment', paymentError.message);
    }

    // Live tracking pings for the in-transit order (vendor → customer path).
    if (plan.status === 'in_transit' && plan.courier) {
      const steps = 9;
      const pings = Array.from({ length: steps }, (_, i) => {
        const t = (i + 1) / (steps + 1);
        const wobble = () => (rand() - 0.5) * 0.0015;
        return {
          delivery_id: deliveryRow.id,
          courier_id: plan.courier!.id,
          lat: vendor.lat + (dropoff.lat - vendor.lat) * t + wobble(),
          lng: vendor.lng + (dropoff.lng - vendor.lng) * t + wobble(),
          recorded_at: minutesAgo((steps - i) * 2).toISOString(),
        };
      });
      const { error: pingsError } = await supabaseAdmin.from('location_pings').insert(pings);
      if (pingsError) fail('creating location pings', pingsError.message);
      inTransitInfo = { deliveryId: deliveryRow.id as string, courier: plan.courier };

      // Park the courier at their latest ping so dispatch data is coherent.
      const last = pings[pings.length - 1];
      await supabaseAdmin
        .from('users')
        .update({ last_lat: last.lat, last_lng: last.lng, last_seen_at: last.recorded_at })
        .eq('id', plan.courier.id);
    }

    // Reviews on ~70% of delivered orders.
    if (delivered && rand() < 0.7) {
      const rating = pick([5, 5, 5, 4, 4, 4, 5, 3]);
      reviewRows.push({
        order_id: orderId,
        vendor_id: vendor.id,
        customer_id: customer.id,
        rating,
        comment: rand() < 0.85 ? pick(REVIEW_COMMENTS[rating]) : null,
        created_at: new Date(updatedAt.getTime() + randInt(1, 12) * 3_600_000).toISOString(),
      });
    }

    // A few inbox notifications so the demo accounts aren't empty.
    if (plan.minutesActive !== undefined || plan.daysBack <= 3) {
      const statusTitles: Record<string, [string, string]> = {
        paid: ['Payment confirmed', `Your order from ${vendor.name} is confirmed.`],
        preparing: ['Order being prepared', `${vendor.name} is preparing your order.`],
        ready_for_pickup: ['Order ready', `Your order from ${vendor.name} is ready for pickup.`],
        in_transit: ['Courier on the way', `Your order from ${vendor.name} is out for delivery.`],
        delivered: ['Order delivered', `Your order from ${vendor.name} has been delivered. Enjoy!`],
      };
      const note = statusTitles[plan.status];
      if (note) {
        notificationRows.push({
          user_id: customer.id,
          title: note[0],
          body: note[1],
          data: { order_id: orderId, status: plan.status },
          read: plan.status === 'delivered' && rand() < 0.5,
          created_at: updatedAt.toISOString(),
        });
      }
      notificationRows.push({
        user_id: vendor.ownerId,
        title: 'New order received',
        body: `Order for $${(total / 100).toFixed(2)} — ${items.length} item(s).`,
        data: { order_id: orderId },
        read: plan.daysBack > 0,
        created_at: createdAt.toISOString(),
      });
    }
  }

  // A month of completed history…
  for (let i = 0; i < 28; i++) {
    await createOrder({ status: 'delivered', daysBack: randInt(1, 30), courier: pick(couriers) });
  }
  // …a couple of cancellations…
  await createOrder({ status: 'cancelled', daysBack: randInt(4, 20), courier: null });
  await createOrder({ status: 'cancelled', daysBack: randInt(4, 20), courier: null });
  // …and a live board covering every active state for the demo walkthrough.
  await createOrder({ status: 'pending_payment', daysBack: 0, courier: null, minutesActive: 6 });
  await createOrder({ status: 'paid', daysBack: 0, courier: null, minutesActive: 14 });
  await createOrder({ status: 'accepted', daysBack: 0, courier: null, minutesActive: 22 });
  await createOrder({ status: 'preparing', daysBack: 0, courier: null, minutesActive: 28 });
  await createOrder({ status: 'ready_for_pickup', daysBack: 0, courier: null, minutesActive: 35 });
  await createOrder({ status: 'ready_for_pickup', daysBack: 0, courier: null, minutesActive: 41 });
  await createOrder({ status: 'courier_assigned', daysBack: 0, courier: couriers[1], minutesActive: 33 });
  await createOrder({ status: 'picked_up', daysBack: 0, courier: couriers[2], minutesActive: 39 });
  await createOrder({ status: 'in_transit', daysBack: 0, courier: couriers[0], minutesActive: 47 });

  console.log('Creating reviews…');
  if (reviewRows.length > 0) {
    const { error } = await supabaseAdmin.from('reviews').insert(reviewRows);
    if (error) fail('creating reviews', error.message);
  }

  // Roll review aggregates up onto the vendors (what the storefront sorts by).
  for (const vendor of vendors) {
    const vendorReviews = reviewRows.filter((r) => r.vendor_id === vendor.id);
    if (vendorReviews.length === 0) continue;
    const avg = vendorReviews.reduce((sum, r) => sum + r.rating, 0) / vendorReviews.length;
    const { error } = await supabaseAdmin
      .from('vendors')
      .update({ rating_avg: Math.round(avg * 100) / 100, rating_count: vendorReviews.length })
      .eq('id', vendor.id);
    if (error) fail(`updating rating for ${vendor.name}`, error.message);
  }

  console.log('Creating notifications…');
  if (notificationRows.length > 0) {
    const { error } = await supabaseAdmin.from('notifications').insert(notificationRows);
    if (error) fail('creating notifications', error.message);
  }

  console.log(`
Seed complete ✅
  vendors:        ${vendors.length} (all approved, with menus)
  products:       ${vendors.reduce((n, v) => n + v.products.length, 0)}
  customers:      ${customers.length}   couriers: ${couriers.length}
  orders:         ${orderCount} (28 delivered, 2 cancelled, 9 live across every status)
  reviews:        ${reviewRows.length} (vendor ratings updated)
  notifications:  ${notificationRows.length}
  promo codes:    WELCOME10, SAVE5, SUMMER25 (+1 expired)
  live tracking:  in-transit order has GPS pings${inTransitInfo ? ` (courier ${inTransitInfo.courier.full_name})` : ''}

Demo logins (password for all: ${DEMO_PASSWORD})
  customer  → customer${DEMO_DOMAIN}
  vendor    → vendor${DEMO_DOMAIN}   (Bella Napoli Pizzeria)
  courier   → courier${DEMO_DOMAIN}
  admin     → admin${DEMO_DOMAIN}
`);
}

main().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
