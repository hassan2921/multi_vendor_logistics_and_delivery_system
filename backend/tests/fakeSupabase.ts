/**
 * Minimal in-memory stand-in for the subset of the supabase-js query
 * builder our services use, so idempotency/orders/stripe logic can be
 * unit-tested without a real Supabase project.
 */

type Row = Record<string, unknown>;

const UNIQUE_COLUMNS: Record<string, string[]> = {
  idempotency_keys: ['key'],
  stripe_events_seen: ['event_id'],
  vendors: ['owner_user_id'],
};

class FakeQueryBuilder {
  private op: 'select' | 'insert' | 'update' | 'delete' | null = null;
  private payload: Row | Row[] | null = null;
  private filters: { col: string; val: unknown; matcher: (rowVal: unknown, val: unknown) => boolean }[] = [];
  private orderBy: { col: string; ascending: boolean } | null = null;
  private limitCount: number | null = null;

  constructor(private table: string, private store: Map<string, Row[]>) {}

  insert(payload: Row | Row[]) {
    this.op = 'insert';
    this.payload = payload;
    return this;
  }

  update(payload: Row) {
    this.op = 'update';
    this.payload = payload;
    return this;
  }

  delete() {
    this.op = 'delete';
    return this;
  }

  select(_columns?: string) {
    if (!this.op) this.op = 'select';
    return this;
  }

  eq(col: string, val: unknown) {
    this.filters.push({ col, val, matcher: (rowVal, v) => rowVal === v });
    return this;
  }

  is(col: string, val: unknown) {
    // Postgres treats a column that was never set as NULL, so undefined
    // must match `is(col, null)` here too.
    this.filters.push({ col, val, matcher: (rowVal, v) => (rowVal ?? null) === v });
    return this;
  }

  in(col: string, vals: unknown[]) {
    this.filters.push({ col, val: vals, matcher: (rowVal, v) => (v as unknown[]).includes(rowVal) });
    return this;
  }

  order(col: string, opts?: { ascending?: boolean }) {
    this.orderBy = { col, ascending: opts?.ascending ?? true };
    return this;
  }

  limit(count: number) {
    this.limitCount = count;
    return this;
  }

  private rows(): Row[] {
    return this.store.get(this.table) ?? [];
  }

  private matches(row: Row): boolean {
    return this.filters.every((f) => f.matcher(row[f.col], f.val));
  }

  private execute(): { data: Row[] | null; error: { message: string } | null } {
    const rows = this.rows();

    if (this.op === 'select') {
      let result = rows.filter((r) => this.matches(r));
      if (this.orderBy) {
        const { col, ascending } = this.orderBy;
        result = [...result].sort((a, b) => {
          const av = a[col] as string | number;
          const bv = b[col] as string | number;
          if (av === bv) return 0;
          const cmp = av < bv ? -1 : 1;
          return ascending ? cmp : -cmp;
        });
      }
      if (this.limitCount !== null) {
        result = result.slice(0, this.limitCount);
      }
      return { data: result, error: null };
    }

    if (this.op === 'insert') {
      const items = Array.isArray(this.payload) ? this.payload : [this.payload as Row];
      const uniqueCols = UNIQUE_COLUMNS[this.table] ?? [];

      for (const item of items) {
        for (const col of uniqueCols) {
          if (rows.some((r) => r[col] === item[col])) {
            return { data: null, error: { message: `duplicate key value violates unique constraint (${col})` } };
          }
        }
      }

      const inserted = items.map((item) => ({
        id: item.id ?? `fake-${this.table}-${Math.random().toString(36).slice(2, 10)}`,
        created_at: new Date().toISOString(),
        ...item,
      }));
      rows.push(...inserted);
      this.store.set(this.table, rows);
      return { data: inserted, error: null };
    }

    if (this.op === 'update') {
      const matched = rows.filter((r) => this.matches(r));
      matched.forEach((r) => Object.assign(r, this.payload));
      return { data: matched, error: null };
    }

    if (this.op === 'delete') {
      const remaining = rows.filter((r) => !this.matches(r));
      this.store.set(this.table, remaining);
      return { data: null, error: null };
    }

    return { data: null, error: { message: 'no operation specified' } };
  }

  single() {
    const { data, error } = this.execute();
    if (error) return Promise.resolve({ data: null, error });
    const row = data?.[0];
    if (!row) return Promise.resolve({ data: null, error: { message: 'no rows found' } });
    return Promise.resolve({ data: row, error: null });
  }

  maybeSingle() {
    const { data, error } = this.execute();
    if (error) return Promise.resolve({ data: null, error });
    return Promise.resolve({ data: data?.[0] ?? null, error: null });
  }

  // Makes `await builder` work when callers don't call .single()/.maybeSingle().
  then<T>(
    onfulfilled?: ((value: { data: Row[] | null; error: { message: string } | null }) => T) | null
  ) {
    return Promise.resolve(this.execute()).then(onfulfilled ?? undefined);
  }
}

export class FakeSupabaseClient {
  store = new Map<string, Row[]>();

  auth = {
    getUser: async (_token: string) => ({ data: { user: null }, error: { message: 'not implemented in fake' } }),
    admin: {
      createUser: async (_opts: unknown) => ({ data: { user: null }, error: { message: 'not implemented in fake' } }),
      deleteUser: async (_id: string) => ({ data: null, error: null }),
    },
  };

  from(table: string) {
    return new FakeQueryBuilder(table, this.store);
  }

  reset() {
    this.store.clear();
  }
}

export const fakeSupabase = new FakeSupabaseClient();
