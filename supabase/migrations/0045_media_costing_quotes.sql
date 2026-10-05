-- =====================================================================
-- 0045 — (1) promotional video + thumbnail (Instagram-reel size, 9:16) for the website cards and the KMR Apps
--            dashboard: KMR Apps, business verticals, shop items / programmes / services;
--        (2) costing catalogue + quotations (KMR Console › Prices & invoices › Quotations), PDF on the letterhead.
-- Needs 0044 and 0018. Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regclass('public.app_listings') is null then raise exception 'Run 0044_website_apps_pricing.sql first.'; end if;
end $$;

-- ---------- 1. promo video + thumbnail ----------
alter table public.app_listings add column if not exists video_url text;
alter table public.app_listings add column if not exists video_poster text;
do $$ begin
  if to_regclass('public.verticals') is not null then
    alter table public.verticals add column if not exists video_url text;
    alter table public.verticals add column if not exists video_poster text;
  end if;
  if to_regclass('public.products') is not null then
    alter table public.products add column if not exists video_url text;
    alter table public.products add column if not exists video_poster text;
  end if;
end $$;

create or replace function public.kmr_software_catalog() returns jsonb
language sql stable security definer set search_path = console, public as $$
  select coalesce(jsonb_agg(jsonb_build_object('code', p.code, 'name', p.name, 'description', p.description, 'app_path', p.app_path,
           'seat_label', p.seat_label, 'version', p.current_version,
           'tagline', l.tagline, 'image_url', nullif(l.image_url, ''), 'listed', coalesce(l.is_active, true),
           'video_url', nullif(l.video_url, ''), 'video_poster', nullif(l.video_poster, ''),
           'features', case when coalesce(l.features, '') = '' then null
                            else (select jsonb_agg(trim(f)) from unnest(string_to_array(l.features, E'\n')) f where trim(f) <> '') end,
           'prices', coalesce((select jsonb_agg(jsonb_build_object('period', x.period, 'amount', x.unit_amount, 'min', x.min_seats) order by x.period)
                                from console.prices x where x.product_code = p.code and x.active and x.currency = 'INR'), '[]'))
         order by coalesce(l.sort_order, p.sort_order), p.sort_order), '[]')
    from console.products p left join public.app_listings l on l.code = p.code
   where p.active
$$;
grant execute on function public.kmr_software_catalog() to anon, authenticated;

-- ---------- 2. costing catalogue ----------
-- Everything a quotation can be built from besides the per-user subscription prices: implementation, data migration,
-- training, customisation, AMC, hardware, travel … with the basis it is charged on.
create table if not exists console.cost_items (
  id           uuid primary key default gen_random_uuid(),
  product_code text references console.products(code) on delete cascade,     -- null = any product / general service
  name         text not null check (length(trim(name)) between 2 and 160),
  detail       text check (length(detail) <= 400),
  basis        text not null default 'one_time' check (basis in ('one_time','per_month','per_year','per_user_month','per_user_year','per_day','per_hour','per_unit')),
  amount       numeric(12,2) not null default 0 check (amount >= 0),
  default_qty  numeric(10,2) not null default 1 check (default_qty > 0),
  include_by_default boolean not null default false,                        -- added automatically when the product is quoted
  sort_order   integer not null default 100,
  active       boolean not null default true,
  updated_at   timestamptz not null default now()
);
alter table console.cost_items enable row level security;
drop policy if exists cost_items_staff on console.cost_items;
create policy cost_items_staff on console.cost_items for all to authenticated using (console.is_staff()) with check (console.is_staff());

insert into console.cost_items (product_code, name, detail, basis, amount, default_qty, include_by_default, sort_order)
select v.* from (values
  (null::text, 'Implementation & configuration', 'Company set-up, masters, roles, workflows and approvals as agreed in the scope', 'one_time', 50000::numeric, 1::numeric, true, 10),
  (null, 'Initial data migration from Excel', 'Import of existing masters and open transactions from the customer''s Excel files', 'one_time', 15000, 1, true, 20),
  (null, 'User training & go-live support', 'Role-wise training (online or at the plant) and hand-holding in the first weeks', 'one_time', 20000, 1, true, 30),
  (null, 'Customisation / special reports', 'Changes beyond the standard product, estimated in developer days', 'per_day', 8000, 1, false, 40),
  (null, 'On-site visit', 'Engineer at the customer''s plant (travel and stay extra at actuals)', 'per_day', 6000, 1, false, 50),
  (null, 'Annual support & maintenance (AMC)', 'Priority support, health checks and quarterly review — from year 2', 'per_year', 30000, 1, false, 60),
  ('hrm', 'Biometric device integration', 'eSSL / ZKTeco device set-up and live attendance push, per device', 'per_unit', 3500, 1, false, 70),
  ('balloon', 'Drawing ballooning service', 'Our engineers balloon existing drawings for you, per drawing', 'per_unit', 400, 10, false, 80),
  ('calib', 'Gauge QR labels', 'Printed weather-proof QR labels for instruments, per label', 'per_unit', 25, 100, false, 90)
) v(product_code, name, detail, basis, amount, default_qty, include_by_default, sort_order)
where not exists (select 1 from console.cost_items);

-- ---------- 3. quotations ----------
alter table console.billing_settings add column if not exists letterhead_path text;     -- kmr-billing storage; empty = the built-in letterhead
alter table console.billing_settings add column if not exists quote_prefix text not null default 'KMR/QT';
alter table console.billing_settings add column if not exists quote_validity_days integer not null default 30 check (quote_validity_days between 1 and 180);
alter table console.billing_settings add column if not exists quote_terms text default
$t$Payment: 50% with the purchase order, 30% on user acceptance (UAT) and 20% on go-live.
Subscription: 12 months from the agreed activation / go-live date; renewal at the then-current price list.
Customisation, third-party integrations, API work, special reports or major workflow changes are quoted separately.
The customer provides accurate master data and authorised user details for implementation.
The implementation timeline is agreed together, based on data readiness and the approved scope.
GST and statutory taxes are charged as applicable under Indian law.
Travel and on-site expenses outside the agreed scope are charged separately with prior approval.$t$;
alter table console.billing_settings add column if not exists quote_includes text default
$t$Cloud application access for the subscribed organisation and agreed scope
Cloud database storage, daily backups and standard application maintenance
Access from laptop, desktop, tablet, Android and iOS (browser / installable app)
Product updates, bug fixes and technical support during the active subscription
Customer data kept separate from every other customer organisation$t$;

create table if not exists console.quotes (
  id             uuid primary key default gen_random_uuid(),
  number         text unique,                            -- given when the quote is first saved
  customer_id    uuid references console.customers(id) on delete set null,
  to_name        text not null default '',               -- company (also for prospects who are not customers yet)
  to_attn        text, to_address text, to_gstin text, to_email text, to_phone text,
  subject        text not null default '',
  intro          text,
  scope          jsonb not null default '[]',            -- [{module, capability}]
  lines          jsonb not null default '[]',            -- [{particulars, detail, basis, qty, rate, months, amount}]
  includes       text, terms text,
  discount_pct   numeric(5,2) not null default 0 check (discount_pct between 0 and 100),
  gst_rate       numeric(5,2) not null default 18 check (gst_rate between 0 and 40),
  subtotal       numeric(14,2) not null default 0,
  discount       numeric(14,2) not null default 0,
  taxable        numeric(14,2) not null default 0,
  gst            numeric(14,2) not null default 0,
  total          numeric(14,2) not null default 0,
  currency       text not null default 'INR',
  quote_date     date not null default ((now() at time zone 'Asia/Kolkata')::date),
  valid_until    date,
  status         text not null default 'draft' check (status in ('draft','sent','accepted','declined','expired')),
  notes          text,                                   -- internal
  created_by     text, updated_by text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists quotes_created on console.quotes (created_at desc);
alter table console.quotes enable row level security;
drop policy if exists quotes_staff on console.quotes;
create policy quotes_staff on console.quotes for all to authenticated using (console.is_staff()) with check (console.is_staff());

-- KMR/QT/2026/001 — numbered per calendar year
create or replace function console.next_quote_number() returns text language plpgsql security definer set search_path = console, public as $$
declare pre text; yr text := to_char((now() at time zone 'Asia/Kolkata'), 'YYYY'); n int;
begin
  select coalesce(nullif(trim(quote_prefix), ''), 'KMR/QT') into pre from console.billing_settings where id;
  perform pg_advisory_xact_lock(hashtext('kmr-quote-' || yr));
  select coalesce(max(nullif(regexp_replace(split_part(number, '/', array_length(string_to_array(number, '/'), 1)), '\D', '', 'g'), '')::int), 0) + 1 into n
    from console.quotes where number like coalesce(pre, 'KMR/QT') || '/' || yr || '/%';
  return coalesce(pre, 'KMR/QT') || '/' || yr || '/' || lpad(n::text, 3, '0');
end $$;
revoke all on function console.next_quote_number() from public, anon;
grant execute on function console.next_quote_number() to authenticated;
