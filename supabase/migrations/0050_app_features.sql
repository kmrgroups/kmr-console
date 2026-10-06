-- =====================================================================
-- 0050 — Feature-based pricing. Every app has a catalogue of FEATURES, each with its own (editable) price.
--   • An app's price = the sum of the features chosen. Quotations and invoices pick the app, then its features.
--   • Prices: per user (per employee for HRM) per month and per year, plus an optional one-time set-up fee.
--   • "Core" features are the base of the app and are always included.
--   • Any NEW app added to console.products automatically gets a "Core platform" feature, so upcoming apps follow the same flow.
--   • The app's full price in console.prices (INR) is kept equal to the sum of all its active features.
-- Needs 0018 and 0045. Safe to re-run.
-- =====================================================================
do $$ begin
  if to_regclass('console.prices') is null then raise exception 'Run 0018_billing.sql first.'; end if;
end $$;

create table if not exists console.app_features (
  id           uuid primary key default gen_random_uuid(),
  product_code text not null references console.products(code) on delete cascade,
  name         text not null check (length(trim(name)) between 2 and 120),
  detail       text check (length(detail) <= 300),
  is_core      boolean not null default false,
  price_month  numeric(12,2) not null default 0 check (price_month >= 0),   -- per user / employee / month, INR, before GST
  price_year   numeric(12,2) not null default 0 check (price_year >= 0),    -- per user / employee / year
  setup_fee    numeric(12,2) not null default 0 check (setup_fee >= 0),     -- one-time, when this feature is first taken
  sort_order   integer not null default 100,
  active       boolean not null default true,
  updated_at   timestamptz not null default now(),
  unique (product_code, name)
);
create index if not exists app_features_product on console.app_features (product_code, sort_order);
alter table console.app_features enable row level security;
drop policy if exists app_features_read on console.app_features;
create policy app_features_read on console.app_features for select to authenticated using (console.is_staff());
drop policy if exists app_features_write on console.app_features;
create policy app_features_write on console.app_features for all to authenticated using (console.is_manager()) with check (console.is_manager());
revoke all on console.app_features from anon;

alter table console.invoice_lines add column if not exists feature_id uuid references console.app_features(id) on delete set null;

-- ---------- the app's full price follows its features ----------
create or replace function console.sync_app_price(p_code text) returns void
language plpgsql security definer set search_path = console, public as $$
declare m numeric; y numeric;
begin
  select coalesce(sum(price_month), 0), coalesce(sum(price_year), 0) into m, y from console.app_features where product_code = p_code and active;
  if m = 0 and y = 0 then return; end if;
  insert into console.prices (product_code, period, currency, unit_amount, note) values (p_code, 'month', 'INR', m, 'Sum of all features')
    on conflict (product_code, period, currency) do update set unit_amount = excluded.unit_amount, note = excluded.note, updated_at = now();
  insert into console.prices (product_code, period, currency, unit_amount, note) values (p_code, 'year', 'INR', y, 'Sum of all features')
    on conflict (product_code, period, currency) do update set unit_amount = excluded.unit_amount, note = excluded.note, updated_at = now();
end $$;
revoke all on function console.sync_app_price(text) from public, anon, authenticated;

create or replace function console.app_features_after() returns trigger
language plpgsql security definer set search_path = console, public as $$
begin
  if tg_op = 'DELETE' then perform console.sync_app_price(old.product_code); return old; end if;
  new.updated_at := coalesce(new.updated_at, now());
  perform console.sync_app_price(new.product_code);
  return new;
end $$;
drop trigger if exists app_features_sync on console.app_features;
create trigger app_features_sync after insert or update or delete on console.app_features for each row execute function console.app_features_after();

-- ---------- every NEW app starts with a core feature, priced from its existing price list (or 0 until set) ----------
create or replace function console.product_core_feature() returns trigger
language plpgsql security definer set search_path = console, public as $$
begin
  insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, sort_order)
  values (new.code, 'Core platform', 'Everything in ' || new.name || ' that every customer needs',  true,
          coalesce((select unit_amount from console.prices where product_code = new.code and period = 'month' and currency = 'INR' and active), 0),
          coalesce((select unit_amount from console.prices where product_code = new.code and period = 'year' and currency = 'INR' and active), 0), 10)
  on conflict (product_code, name) do nothing;
  return new;
end $$;
drop trigger if exists products_core_feature on console.products;
create trigger products_core_feature after insert on console.products for each row execute function console.product_core_feature();

-- ---------- starting catalogue (fixed prices, all editable under Prices & invoices › Features & pricing) ----------
-- price_year = 10 × monthly (two months free); seeded only for apps that have no features yet
create temp table _f (product_code text, name text, detail text, is_core boolean, pm numeric, sf numeric, ord int) on commit preserve rows;
insert into _f values
 ('hrm','Employee records & ID cards','Employee master, documents, self-onboarding with selfie, digital ID card',true,15,0,10),
 ('hrm','Attendance, shifts & leave','Biometric / manual attendance, shift roster, leave balances and approvals',false,15,0,20),
 ('hrm','Payroll & statutory reports','Salary structure, payslips, PF / ESI / PT reports',false,15,0,30),
 ('hrm','Recruitment & onboarding','Openings, applicants, interview pipeline, offer and joining checklist',false,8,0,40),
 ('hrm','Skill matrix, training & safety','IATF-ready skill matrix, training records, safety and compliance logs',false,7,0,50),
 ('balloon','Drawing ballooning','PDF drawings, numbered balloons and characteristic table with SC / CC',true,300,0,10),
 ('balloon','Inspection & first-article reports','FAI and inspection reports with measured values and accept / reject',false,200,0,20),
 ('balloon','CAD formats (DXF, DWG, STEP)','Reads CAD drawings and models, not only PDFs',false,150,0,30),
 ('balloon','Data flow to Process Documents','Characteristics flow into PFMEA, control plan and PPAP',false,100,0,40),
 ('pd','Process flow diagram','Process flow with part, operation and characteristic links',true,300,0,10),
 ('pd','PFMEA (AIAG-VDA and 4th edition)','Toggle between the Action Priority format and the RPN format',false,300,0,20),
 ('pd','Control plan & SOP','Control plan and standard operating procedures from the flow',false,250,0,30),
 ('pd','Setup, patrol & PDI sheets','Set-up, patrol, self-inspection and pre-delivery inspection sheets',false,150,0,40),
 ('pd','SPC studies','Control charts, Cp / Cpk and trend alerts',false,200,0,50),
 ('pd','MSA / Gauge R&R studies','Gauge R&R, bias, linearity and attribute studies',false,150,0,60),
 ('capacity','Monthly plan & machine loading','Part-wise monthly plan against machine capacity',true,400,0,10),
 ('capacity','Takt time & levelling','Takt time, load levelling and bottleneck view',false,200,0,20),
 ('capacity','Alternate machines & what-if','Alternate machine routing and what-if plans',false,200,0,30),
 ('sales','Monthly plan from Operations Master','Plan every part every month from rate contracts',true,300,0,10),
 ('sales','Daily despatch & ABC analysis','Despatch against plan, pending and ABC analysis',false,250,0,20),
 ('sales','Loss reasons & action plans','Loss reasons with owners, dates and follow-up',false,150,0,30),
 ('calib','Instrument register & QR labels','Gauge register, QR labels and history',true,250,0,10),
 ('calib','Due alerts & certificates','Calibration due alerts and certificate store',false,200,0,20),
 ('calib','Out-of-tolerance cases','Impact assessment and corrective action on failed gauges',false,100,0,30),
 ('calib','Gauge R&R (MSA)','MSA studies linked to control plans',false,200,0,40),
 ('apqp','Programmes & five phases','Programmes, five APQP phases and deliverables with owners and due dates',true,300,0,10),
 ('apqp','Deliverable tracker & gate sign-offs','Phase gates, sign-offs and overdue alerts',false,250,0,20),
 ('apqp','Evidence from other KMR apps','Links to drawings, PFMEA, control plans and gauges — no re-entry',false,150,0,30),
 ('ppap','Submissions & the 18 elements','Submission level 1–5 and the 18 PPAP elements',true,300,0,10),
 ('ppap','Part Submission Warrant','Auto-filled PSW with sign-off',false,250,0,20),
 ('ppap','Evidence assembly from KMR apps','Pulls ballooned drawings, PFMEA, control plan and MSA into the file',false,200,0,30);
insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, setup_fee, sort_order)
select f.product_code, f.name, f.detail, f.is_core, f.pm, f.pm * 10, f.sf, f.ord from _f f
 where exists (select 1 from console.products p where p.code = f.product_code)
   and not exists (select 1 from console.app_features a where a.product_code = f.product_code)
on conflict (product_code, name) do nothing;
-- any app still without features (e.g. added earlier) gets its core feature now
insert into console.app_features (product_code, name, detail, is_core, price_month, price_year, sort_order)
select p.code, 'Core platform', 'Everything in ' || p.name || ' that every customer needs', true,
       coalesce((select unit_amount from console.prices where product_code = p.code and period = 'month' and currency = 'INR' and active), 0),
       coalesce((select unit_amount from console.prices where product_code = p.code and period = 'year' and currency = 'INR' and active), 0), 10
  from console.products p where p.code <> 'console' and not exists (select 1 from console.app_features a where a.product_code = p.code)
on conflict (product_code, name) do nothing;
do $$ declare r record; begin for r in select distinct product_code from console.app_features loop perform console.sync_app_price(r.product_code); end loop; end $$;

-- ---------- invoices: one line per chosen feature ----------
create or replace function console.create_invoice(p_customer uuid, p_period text, p_from date, p_items jsonb, p_notes text default null) returns uuid
language plpgsql security definer set search_path = console, public as $$
declare c console.customers; it jsonb; pr console.prices; prod console.products; f console.app_features; q numeric; inv uuid; n int := 0; pto date;
        fid text; setup numeric; per text;
begin
  perform console.require_manager();
  select * into c from console.customers where id = p_customer;
  if c.id is null then raise exception 'Customer not found.'; end if;
  if p_period not in ('month','year') then raise exception 'Choose monthly or yearly billing.'; end if;
  if p_from is null then raise exception 'Choose the date the billed period starts.'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 then raise exception 'Pick at least one product to bill.'; end if;
  pto := (p_from + case when p_period = 'year' then interval '1 year' else interval '1 month' end - interval '1 day')::date;
  per := case when p_period = 'year' then 'yearly' else 'monthly' end;
  insert into console.invoices (customer_id, period, currency, notes, created_by)
  values (c.id, p_period, c.currency, nullif(trim(coalesce(p_notes, '')), ''), auth.uid()) returning id into inv;
  for it in select * from jsonb_array_elements(p_items) loop
    select * into prod from console.products where code = it ->> 'product_code';
    if prod.code is null then raise exception 'Unknown product %.', it ->> 'product_code'; end if;
    select * into pr from console.prices where product_code = prod.code and period = p_period and currency = c.currency and active;
    if jsonb_typeof(it -> 'features') = 'array' and jsonb_array_length(it -> 'features') > 0 then
      -- priced by the features chosen
      if c.currency <> 'INR' then raise exception 'Feature prices are in INR. This customer is billed in %, so use the whole-app price (no features) for %.', c.currency, prod.name; end if;
      q := greatest(coalesce(nullif(it ->> 'seats', '')::numeric, 0), coalesce(pr.min_seats, 1));
      setup := 0;
      -- core features are always billed
      for f in select * from console.app_features where product_code = prod.code and active
                  and (is_core or id::text in (select jsonb_array_elements_text(it -> 'features'))) order by sort_order, name loop
        n := n + 1;
        insert into console.invoice_lines (invoice_id, sort, product_code, feature_id, description, period_from, period_to, qty, unit_amount, amount)
        values (inv, n, prod.code, f.id, prod.name || ' — ' || f.name || ' (' || per || ', ' || q::int || ' ' || prod.seat_label || ')', p_from, pto, q,
                case when p_period = 'year' then f.price_year else f.price_month end,
                round(q * case when p_period = 'year' then f.price_year else f.price_month end, 2));
        setup := setup + f.setup_fee;
      end loop;
      if setup > 0 then
        n := n + 1;
        insert into console.invoice_lines (invoice_id, sort, description, qty, unit_amount, amount)
        values (inv, n, prod.name || ' — one-time set-up of the chosen features', 1, setup, setup);
      end if;
    else
      if pr.id is null then
        raise exception 'There is no % price in % for %. Add it under Prices & invoices first.', per, c.currency, prod.name;
      end if;
      q := greatest(coalesce(nullif(it ->> 'seats', '')::numeric, 0), pr.min_seats);
      n := n + 1;
      insert into console.invoice_lines (invoice_id, sort, product_code, description, period_from, period_to, qty, unit_amount, amount)
      values (inv, n, prod.code, prod.name || ' — ' || per || ' subscription, ' || q::int || ' ' || prod.seat_label, p_from, pto, q, pr.unit_amount, round(q * pr.unit_amount, 2));
    end if;
  end loop;
  perform console.invoice_recalc(inv);
  return inv;
end $$;
revoke all on function console.create_invoice(uuid, text, date, jsonb, text) from public, anon;
grant execute on function console.create_invoice(uuid, text, date, jsonb, text) to authenticated;
drop table if exists _f;
